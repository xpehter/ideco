#!/bin/bash

# Логирование https://habr.com/ru/post/281601/
#exec > >(logger  -p local0.notice -t $(basename "$0"))
#exec 2> >(logger  -p local0.error -t $(basename "$0"))

# Переменные
CERT_NEW='/tmp/help.ideco.ru.crt'
CERT_NEW_PATH='/root/.acme.sh/help.ideco.ru/'
CERT_OLD='/tmp/help.ideco.ru.crt_old'
UTM_IP='10.80.1.1'
UTM_PASS="$(cat /root/.ssh/utm_pass)"
UTM_USER='root'
UTM_CERT='/var/opt/ideco/nginx_reverse_proxy/user_certs/help.ideco.ru.crt'

# Знаю про http://porkmail.org/era/unix/award.html#cat
cat "${CERT_NEW_PATH}"help.ideco.ru.key > "${CERT_NEW}"
echo '' >> "${CERT_NEW}" # Для красоты
cat "${CERT_NEW_PATH}"fullchain.cer >> "${CERT_NEW}"

# TODO (xpeh): Проверка на запуск с правами root'а, иначе рядом пишем лог об этом

# TODO (xpeh): Проверка наличия sshpass, иначе пишем в лог

sshpass -p "${UTM_PASS}" scp -q -o StrictHostKeyChecking=no -o "UserKnownHostsFile /dev/null" "${UTM_USER}"@"${UTM_IP}":"${UTM_CERT}" "${CERT_OLD}"
#cat "${CERT_OLD}"

# Убираем за собой
rm -rf "${CERT_NEW}" "${CERT_OLD}"