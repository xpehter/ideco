#!/bin/bash

# Логирование https://habr.com/ru/post/281601/
#exec > >(logger  -p local0.notice -t $(basename "$0"))
#exec 2> >(logger  -p local0.error -t $(basename "$0"))

# TODO (xpeh): Проверка на запуск с правами root'а, иначе рядом пишем лог об этом
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Переменные
CERT_NEW='/tmp/help.ideco.ru.crt'
CERT_NEW_ACME_PATH='/root/.acme.sh/help.ideco.ru/'
CERT_OLD='/tmp/help.ideco.ru.crt_old'
UTM_IP='10.80.1.1'
UTM_PASS="$(cat /root/.ssh/utm_pass)"
UTM_USER='root'
UTM_CERT='/var/opt/ideco/nginx_reverse_proxy/user_certs/help.ideco.ru.crt'

# Знаю про http://porkmail.org/era/unix/award.html#cat
cat "${CERT_NEW_ACME_PATH}"help.ideco.ru.key > "${CERT_NEW}"
echo '' >> "${CERT_NEW}" # Для красоты
cat "${CERT_NEW_ACME_PATH}"fullchain.cer >> "${CERT_NEW}"

# TODO (xpeh): Проверка наличия sshpass, иначе пишем в лог

sshpass -p "${UTM_PASS}" scp -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${UTM_USER}"@"${UTM_IP}":"${UTM_CERT}" "${CERT_OLD}"

# Проверив, что сертификат имеется, вытаскиваем из него дату окончания и приводим её к формату Unix Epoch, ибо так удобнее сравнивать
if test -f "${CERT_NEW}"; then
  CERT_NEW_END_DATE="$(date "+%s" --date="$(openssl x509 -in "${CERT_NEW}" -noout -enddate | cut -d= -f 2)")"
else
  echo "Missing ${CERT_NEW}" >&2
  exit 1
fi
if test -f "${CERT_OLD}"; then
  CERT_OLD_END_DATE="$(date "+%s" --date="$(openssl x509 -in "${CERT_OLD}" -noout -enddate | cut -d= -f 2)")"
else
  echo "Missing ${CERT_OLD}" >&2
  exit 1
fi

if [ "${CERT_NEW_END_DATE}" -gt "${CERT_OLD_END_DATE}" ]; then
  # В начале нужно менять в /var/opt/ideco/reverse_proxy_backend/storage.db , ибо именно там reverse_proxy_backend хранит сертификаты
  
  sshpass -p "${UTM_PASS}" scp -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${CERT_NEW}" "${UTM_USER}"@"${UTM_IP}":"${UTM_CERT}"
  # PID nginx'а для reverse proxy указан в конфиге /var/opt/ideco/nginx_reverse_proxy/nginx.conf
  sshpass -p "${UTM_PASS}" ssh -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${UTM_USER}"@"${UTM_IP}" 'kill -HUP $(cat /tmp/nginx_reverse_proxy.pid)'
  echo "Certificate "$(openssl x509 -in "${CERT_OLD}" -noout -enddate | cut -d= -f 2)" has been replaced with certificate "$(openssl x509 -in "${CERT_NEW}" -noout -enddate | cut -d= -f 2)"" >&1
else
  echo "Certificate "$(openssl x509 -in "${CERT_OLD}" -noout -enddate | cut -d= -f 2)" does not require replacement with certificate "$(openssl x509 -in "${CERT_NEW}" -noout -enddate | cut -d= -f 2)"" >&1
fi
# Убираем за собой
rm -rf "${CERT_NEW}" "${CERT_OLD}"