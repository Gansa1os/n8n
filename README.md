# n8n Auto Installer (User Edition)

Упрощённый скрипт `install-n8n-user.sh` разворачивает n8n + Traefik + Redis в Docker на Ubuntu 20.04/22.04/24.04 LTS и спрашивает только три значения: домен, email и пароль для входа.

## Требования

- Чистый VPS/VDS с Ubuntu 20.04, 22.04 или 24.04 LTS.
- Root-доступ (запуск через `root` или `sudo -i`).
- Настроенные DNS-записи на нужный домен/поддомен.
- Открытые TCP-порты 80 и 443.

## Установка

```bash
git clone https://github.com/<your-org>/<repo>.git
cd <repo>
chmod +x install-n8n-user.sh
sudo ./install-n8n-user.sh
```

Во время работы скрипт:

1. Проверяет версию Ubuntu и наличие Docker/Compose (при необходимости установит).
2. Запрашивает домен (`n8n.example.com`), email (идентичен логину) и пароль.
3. Генерирует `.env`, `docker-compose.yml`, `custom/Dockerfile` и `local-files/` в `n8n-compose/`.
4. Запускает `docker compose up -d` и включает systemd-сервис `n8n.service`.

После успешного запуска:

- n8n доступен по `https://<ваш-домен>` с Basic Auth (логин = введённый email, пароль = введённый пароль).
- Traefik dashboard доступен по `https://traefik.<основной-домен>`.
- Данные n8n лежат в `n8n-compose/n8n_data` (Docker volume), локальные файлы — в `n8n-compose/local-files`.

## Управление

Находясь в каталоге со скриптом:

```bash
sudo ./install-n8n-user.sh --update   # подтянуть свежие образы и перезапустить
sudo ./install-n8n-user.sh --stop     # остановить n8n и Traefik
sudo ./install-n8n-user.sh --restart  # перезапустить стэк
sudo ./install-n8n-user.sh --check    # проверка .env и docker-compose.yml
```

systemd-сервис:

```bash
sudo systemctl status n8n
sudo systemctl restart n8n
sudo journalctl -u n8n -e
```

## Частые вопросы

- **Как сменить логин/пароль?** Отредактируйте `n8n-compose/.env` (`N8N_BASIC_AUTH_*`) и выполните `cd n8n-compose && docker compose up -d`.
- **Можно ли подключить PostgreSQL?** Да: заполните переменные `DB_*` в `n8n-compose/.env` и перезапустите контейнеры.
- **Где лежат сертификаты?** В volume `traefik_data` (`n8n-compose/letsencrypt/acme.json` внутри контейнера Traefik).
- **Как сделать бэкап?** Сохраните volume `n8n_data` (``docker run --rm -v n8n-compose_n8n_data:/data -v $(pwd):/backup alpine tar czf /backup/n8n_data.tar.gz /data``) и рабочие файлы из `n8n-compose/`.

Готово — можно выкладывать репозиторий на GitHub и делиться скриптом с пользователями.
