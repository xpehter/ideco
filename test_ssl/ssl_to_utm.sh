#!/bin/bash
#
# Обновление SSL-сертификата на UTM, выпущенного через Let’s Encrypt acme.sh'ем

# Логирование https://habr.com/ru/post/281601/
#exec > >(logger  -p local0.notice -t $(basename "$0"))
#exec 2> >(logger  -p local0.error -t $(basename "$0"))

# TODO (xpeh): Проверка на запуск с правами root'а, иначе рядом пишем лог об этом
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 1>&2
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
UTM_REVERSE_PROXY_PID='$(cat /tmp/nginx_reverse_proxy.pid)' # PID nginx'а для reverse proxy указан в конфиге /var/opt/ideco/nginx_reverse_proxy/nginx.conf

# Знаю про http://porkmail.org/era/unix/award.html#cat
cat "${CERT_NEW_ACME_PATH}"help.ideco.ru.key > "${CERT_NEW_PATH}"
echo '' >> "${CERT_NEW_PATH}" # Для красоты
cat "${CERT_NEW_ACME_PATH}"fullchain.cer >> "${CERT_NEW_PATH}"

# TODO (xpeh): Проверка наличия sshpass, иначе пишем в лог

sshpass -p "${UTM_PASS}" scp -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${UTM_USER}"@"${UTM_IP}":"${UTM_CERT}" "${CERT_OLD}"

# Проверив, что сертификат имеется, вытаскиваем из него дату окончания и приводим её к формату Unix Epoch, ибо так удобнее сравнивать
if test -f "${CERT_NEW_PATH}"; then
  CERT_NEW_QUOTES="'"$(cat "${CERT_NEW_PATH}")"'"
  CERT_NEW_CN="$(openssl x509 -in "${CERT_NEW_PATH}" -noout -subject | cut -d= -f3)"
  CERT_NEW_CN_QUOTES="'""${CERT_NEW_CN}""'"
  CERT_NEW_END_DATE_HUMAN="$(openssl x509 -in "${CERT_NEW_PATH}" -noout -enddate | cut -d= -f2)"
  CERT_NEW_END_DATE="$(date "+%s" --date="${CERT_NEW_END_DATE_HUMAN}")"
else
  echo "Missing ${CERT_NEW_PATH}" >&2
  exit 1
fi
if test -f "${CERT_OLD}"; then
  CERT_OLD_CN="$(openssl x509 -in "${CERT_OLD}" -noout -subject | cut -d= -f3)"
  CERT_OLD_END_DATE_HUMAN="$(openssl x509 -in "${CERT_OLD}" -noout -enddate | cut -d= -f2)"
  CERT_OLD_END_DATE="$(date "+%s" --date="${CERT_OLD_END_DATE_HUMAN}")"
else
  echo "Missing ${CERT_OLD}" >&2
  exit 1
fi

if [ "${CERT_NEW_CN}" == "${CERT_OLD_CN}" ]; then
  if [ "${CERT_NEW_END_DATE}" -gt "${CERT_OLD_END_DATE}" ]; then
    # В начале нужно менять в /var/opt/ideco/reverse_proxy_backend/storage.db , ибо именно там reverse_proxy_backend хранит сертификаты
    
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
    #echo "${QUERY}"
    #sshpass -p "${UTM_PASS}" ssh -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${UTM_USER}"@"${UTM_IP}" "echo -e "${QUERY}" | sqlite3 "${CERT_NEW_DB_PATH}""
    sshpass -p "${UTM_PASS}" ssh -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${UTM_USER}"@"${UTM_IP}" "echo -e "${QUERY}" > /root/d.kondrashov/query"
    sshpass -p "${UTM_PASS}" scp -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${CERT_NEW_PATH}" "${UTM_USER}"@"${UTM_IP}":"${UTM_CERT}"
    sshpass -p "${UTM_PASS}" ssh -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${UTM_USER}"@"${UTM_IP}" "kill -HUP "${UTM_REVERSE_PROXY_PID}""
    echo "Certificate "${CERT_NEW_CN}" replaced "${CERT_OLD_END_DATE_HUMAN}" -> "${CERT_NEW_END_DATE_HUMAN}"" >&1
  else
    echo "Certificate "${CERT_NEW_CN}" not replacement "${CERT_NEW_END_DATE_HUMAN}" < or = "${CERT_OLD_END_DATE_HUMAN}"" >&1
  fi
else
  echo "Common name different "${CERT_NEW_CN}" != "${CERT_OLD_CN}"">&2
fi
# Убираем за собой
rm -rf "${CERT_NEW_PATH}" "${CERT_OLD}"
