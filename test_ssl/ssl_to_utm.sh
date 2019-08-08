#!/bin/bash
#
# Обновление SSL-сертификата на UTM, выпущенного через Let’s Encrypt acme.sh'ем

# TODO (xpeh): Переписать всё это без сохранения временных файлов и обращения к
#   nginx. По правильному нужно использовать API reverse_proxy_backend и только
#   если в нём нет нужно функционала "спускаться ниже", пользуя запросы к его
#   SQLite-базе и т.д.

# Логирование https://habr.com/ru/post/281601/
#exec > >(logger  -p local0.notice -t $(basename "$0"))
#exec 2> >(logger  -p local0.error -t $(basename "$0"))

# TODO (xpeh): Проверка на запуск с правами root'а,
# иначе рядом пишем лог об этом
if [[ $EUID -ne 0 ]]; then
  printf '%s\n' "This script must be run as root" 1>&2
  exit 1
fi

# Проверка зависимостей:
#   sshpass
type sshpass > /dev/null 2>&1
if [[ "$?" != "0" ]]; then
  printf '%s\n' "Not installed sshpass" >&2
  exit 1
fi

# Переменные
CERT_NEW_PATH='/tmp/help.ideco.ru.crt'
CERT_NEW_ACME_PATH='/root/.acme.sh/help.ideco.ru/'
CERT_NEW_DB_PATH='/var/opt/ideco/reverse_proxy_backend/storage.db'
CERT_OLD='/tmp/help.ideco.ru.crt_old'
UTM_IP='10.80.1.1'
UTM_PASS="$(cat /root/.ssh/utm_pass)"
UTM_USER='root'
UTM_CERT='/var/opt/ideco/nginx_reverse_proxy/user_certs/help.ideco.ru.crt'
# Путь к PID nginx'а для reverse proxy указан в конфиге
# /var/opt/ideco/nginx_reverse_proxy/nginx.conf
UTM_REVERSE_PROXY_PID='$(cat /tmp/nginx_reverse_proxy.pid)'

# Знаю про http://porkmail.org/era/unix/award.html#cat
cat "${CERT_NEW_ACME_PATH}"help.ideco.ru.key > "${CERT_NEW_PATH}"
printf '\n' "" >> "${CERT_NEW_PATH}" # Для красоты
cat "${CERT_NEW_ACME_PATH}"fullchain.cer >> "${CERT_NEW_PATH}"

sshpass -p "${UTM_PASS}" scp -q -o StrictHostKeyChecking=no \
  -o "UserKnownHostsFile /dev/null" \
  "${UTM_USER}"@"${UTM_IP}":"${UTM_CERT}" "${CERT_OLD}"

# Проверив, наличие файла сертификата, вытаскиваем из него дату окончания и
# приводим её к формату Unix Epoch, ибо так удобнее сравнивать
if test -f "${CERT_NEW_PATH}"; then
  # Обмазываем кавычками содержимое переменной для корректного выполнения в SQL-запросе
  CERT_NEW_QUOTES="'"$(cat "${CERT_NEW_PATH}")"'"
  CERT_NEW_CN="$(openssl x509 -in "${CERT_NEW_PATH}" -noout -subject | cut -d= -f3 | xargs)"
  # Обмазываем кавычками содержимое переменной для корректного выполнения в SQL-запросе
  CERT_NEW_CN_QUOTES="'""${CERT_NEW_CN}""'"
  CERT_NEW_END_DATE_HUMAN="$(openssl x509 -in "${CERT_NEW_PATH}" -noout -enddate | cut -d= -f2)"
  CERT_NEW_END_DATE="$(date "+%s" --date="${CERT_NEW_END_DATE_HUMAN}")"
else
  printf '%s\n' "Missing ${CERT_NEW_PATH}" >&2
  exit 1
fi
if test -f "${CERT_OLD}"; then
  CERT_OLD_CN="$(openssl x509 -in "${CERT_OLD}" -noout -subject | cut -d= -f3 | xargs)"
  CERT_OLD_END_DATE_HUMAN="$(openssl x509 -in "${CERT_OLD}" -noout -enddate | cut -d= -f2)"
  CERT_OLD_END_DATE="$(date "+%s" --date="${CERT_OLD_END_DATE_HUMAN}")"
else
  printf '%s\n' "Missing ${CERT_OLD}" >&2
  exit 1
fi

if [ "${CERT_NEW_CN}" == "${CERT_OLD_CN}" ]; then
  if [ "${CERT_NEW_END_DATE}" -gt "${CERT_OLD_END_DATE}" ]; then
    # Формируем SQL-запрос для SQLite-базы reverse_proxy_backend
    IFS_TMP="${IFS}" # Очищаем разделитель (предварительно сделав его бэкап),
    IFS=""           # дабы сохранились переносы строки из сертификата
    # \" - это экранирование кавычек для их подстановки в SSH-команду
    QUERY="\"
    UPDATE
      SiteModel
    SET
      certificate = "${CERT_NEW_QUOTES}"
    WHERE
      id = (
        SELECT
          site
        FROM
          LocationModel
        WHERE
          domain = (
            SELECT
              id
            FROM
              DomainModel
            WHERE
              domain = "${CERT_NEW_CN_QUOTES}"
          )
      );
    \""
    sshpass -p "${UTM_PASS}" ssh -q -o StrictHostKeyChecking=no \
      -o "UserKnownHostsFile /dev/null" \
      "${UTM_USER}"@"${UTM_IP}" "printf '%b' "${QUERY}" | sqlite3 "${CERT_NEW_DB_PATH}""
    IFS="${IFS_TMP}" # Восстанавливаем исходное значение разделителя
    sshpass -p "${UTM_PASS}" scp -q -o StrictHostKeyChecking=no \
      -o "UserKnownHostsFile /dev/null" \
      "${CERT_NEW_PATH}" "${UTM_USER}"@"${UTM_IP}":"${UTM_CERT}"
    sshpass -p "${UTM_PASS}" ssh -q -o StrictHostKeyChecking=no \
      -o "UserKnownHostsFile /dev/null" \
      "${UTM_USER}"@"${UTM_IP}" "kill -HUP "${UTM_REVERSE_PROXY_PID}""
    printf '%s\n' "Certificate ${CERT_NEW_CN} replaced ${CERT_OLD_END_DATE_HUMAN} -> ${CERT_NEW_END_DATE_HUMAN}" >&1
  else
    printf '%s\n' "Certificate ${CERT_NEW_CN} not replacement ${CERT_NEW_END_DATE_HUMAN} < or = ${CERT_OLD_END_DATE_HUMAN}" >&1
  fi
else
  printf '%s\n' "Common name different ${CERT_NEW_CN} != ${CERT_OLD_CN}" >&2
fi
# Убираем за собой
rm -rf "${CERT_NEW_PATH}" "${CERT_OLD}"
