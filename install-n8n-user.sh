#!/bin/bash

# Упрощенный скрипт для установки n8n на Ubuntu VPS.
# Запрашивает только домен, email и пароль для входа в n8n.

set -euo pipefail

# Цвета вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Глобальные переменные
PROJECT_DIR="n8n-compose"
DOMAIN=""
MAIN_DOMAIN=""
SUBDOMAIN=""
SSL_EMAIL=""
ADMIN_PASSWORD=""
ENCRYPTION_KEY=""
ORIGINAL_DIR=""

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_ubuntu_version() {
    print_header "Проверка версии Ubuntu"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $VERSION_ID in
            "20.04"|"22.04"|"24.04")
                print_success "Обнаружена поддерживаемая версия Ubuntu $VERSION_ID LTS"
                ;;
            *)
                print_error "Обнаружена неподдерживаемая версия Ubuntu: $VERSION_ID"
                echo "Поддерживаемые версии: Ubuntu 20.04, 22.04, 24.04 LTS"
                exit 1
                ;;
        esac
    else
        print_error "Не удалось определить версию Ubuntu"
        exit 1
    fi
}

install_docker() {
    print_header "Проверка и установка Docker"

    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        print_success "Docker уже установлен: $DOCKER_VERSION"

        if docker compose version &> /dev/null || docker-compose version &> /dev/null; then
            if docker compose version &> /dev/null; then
                COMPOSE_VERSION=$(docker compose version | cut -d' ' -f4)
                print_success "Docker Compose v2 уже установлен: $COMPOSE_VERSION"
            else
                COMPOSE_VERSION=$(docker-compose version | cut -d' ' -f3)
                print_warning "Обнаружена Docker Compose v1: $COMPOSE_VERSION"
                print_info "Рекомендуется обновить до Docker Compose v2"
            fi
        else
            print_warning "Docker Compose не найден, устанавливаем..."
            install_docker_compose
        fi
    else
        print_warning "Docker не найден, устанавливаем..."
        install_docker_engine
    fi
}

install_docker_engine() {
    print_info "Обновление пакетов..."
    apt update && apt upgrade -y

    print_info "Установка необходимых пакетов..."
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

    print_info "Добавление ключа Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    print_info "Добавление репозитория Docker..."
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    print_info "Установка Docker Engine..."
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io

    print_info "Запуск Docker..."
    systemctl start docker
    systemctl enable docker

    print_success "Docker успешно установлен"
}

install_docker_compose() {
    print_info "Установка Docker Compose v2..."
    apt install -y docker-compose-plugin
    print_success "Docker Compose успешно установлен"
}

generate_encryption_key() {
    if command -v openssl &> /dev/null; then
        ENCRYPTION_KEY=$(openssl rand -hex 32)
    else
        ENCRYPTION_KEY=$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')
    fi
}

gather_user_input() {
    print_header "Сбор данных"

    read -rp "Введите ваш домен (например: n8n.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        print_error "Домен не может быть пустым"
        exit 1
    fi

    if [[ ! $DOMAIN =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Неверный формат домена: $DOMAIN"
        exit 1
    fi

    read -rp "Введите email (используется для Let's Encrypt и входа в n8n): " SSL_EMAIL
    if [ -z "$SSL_EMAIL" ]; then
        print_error "Email не может быть пустым"
        exit 1
    fi

    if [[ ! $SSL_EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Неверный формат email: $SSL_EMAIL"
        exit 1
    fi

    read -rsp "Введите пароль для входа в n8n: " ADMIN_PASSWORD
    echo
    if [ -z "$ADMIN_PASSWORD" ]; then
        print_error "Пароль не может быть пустым"
        exit 1
    fi

    if [[ $DOMAIN =~ ^([^.]+)\.(.*)$ ]]; then
        SUBDOMAIN="${BASH_REMATCH[1]}"
        MAIN_DOMAIN="${BASH_REMATCH[2]}"
    else
        SUBDOMAIN="n8n"
        MAIN_DOMAIN="$DOMAIN"
    fi

    print_success "Домен: $DOMAIN"
    print_info "Субдомен: $SUBDOMAIN"
    print_info "Основной домен: $MAIN_DOMAIN"
    print_success "Email сохранен"

    generate_encryption_key
}

create_config_files() {
    print_header "Создание конфигурации"

    if [ -d "$PROJECT_DIR" ]; then
        print_error "Директория $PROJECT_DIR уже существует. Удалите или переименуйте ее перед запуском."
        exit 1
    fi

    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"

    cat > .env << EOF
DOMAIN_NAME=$MAIN_DOMAIN
SUBDOMAIN=$SUBDOMAIN
SSL_EMAIL=$SSL_EMAIL
GENERIC_TIMEZONE=Europe/Moscow
N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY
N8N_TRUST_PROXY=true
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=$SSL_EMAIL
N8N_BASIC_AUTH_PASSWORD=$ADMIN_PASSWORD
N8N_BASIC_AUTH_HASH=false

DB_TYPE=sqlite
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=change_me
EOF

    cat > docker-compose.yml << 'EOF'
name: n8n

services:
  traefik:
    image: traefik:latest
    restart: always
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.mytlschallenge.acme.tlschallenge=true"
      - "--certificatesresolvers.mytlschallenge.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.mytlschallenge.acme.storage=/letsencrypt/acme.json"
      - "--entrypoints.web.transport.respondingTimeouts.readTimeout=900s"
      - "--entrypoints.web.transport.respondingTimeouts.writeTimeout=900s"
      - "--entrypoints.web.transport.respondingTimeouts.idleTimeout=900s"
      - "--entrypoints.websecure.transport.respondingTimeouts.readTimeout=900s"
      - "--entrypoints.websecure.transport.respondingTimeouts.writeTimeout=900s"
      - "--entrypoints.websecure.transport.respondingTimeouts.idleTimeout=900s"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - traefik_data:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN_NAME}`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=mytlschallenge"
      - "traefik.http.routers.traefik.service=api@internal"

  redis:
    image: redis:7-alpine
    restart: always

  n8n:
    build: ./custom
    image: n8n-with-fonts:latest
    restart: always
    depends_on:
      - redis
    ports:
      - "127.0.0.1:5678:5678"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)"
      - "traefik.http.routers.n8n.entrypoints=web,websecure"
      - "traefik.http.routers.n8n.tls.certresolver=mytlschallenge"
    environment:
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_HOST=${SUBDOMAIN}.${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_RUNNERS_ENABLED=true
      - N8N_RUNNERS_PYTHON_DOCKER_IMAGE=n8n-with-fonts:latest
      - NODE_ENV=production
      - WEBHOOK_URL=https://${SUBDOMAIN}.${DOMAIN_NAME}/
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - TZ=${GENERIC_TIMEZONE}
      - N8N_TRUST_PROXY=${N8N_TRUST_PROXY:-true}
      - N8N_TRUSTED_PROXIES=172.18.0.0/16
      - N8N_SECURITY_TRUSTED_PROXIES=172.18.0.0/16
      - N8N_BASIC_AUTH_ACTIVE=${N8N_BASIC_AUTH_ACTIVE}
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_BASIC_AUTH_HASH=${N8N_BASIC_AUTH_HASH}
      - N8N_RATE_LIMITS_DISABLED=true
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - DB_TYPE=${DB_TYPE:-sqlite}
      - DB_POSTGRESDB_HOST=${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_POSTGRESDB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - NODE_OPTIONS=--max-old-space-size=4096
    mem_limit: 6g
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files
      - /root/output:/data/output:rw

  n8n-worker:
    image: n8n-with-fonts:latest
    command: worker
    restart: always
    depends_on:
      - redis
      - n8n
    environment:
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - DB_TYPE=${DB_TYPE:-sqlite}
      - DB_POSTGRESDB_HOST=${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=${DB_POSTGRESDB_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_BINARY_DATA_MODE=filesystem
      - N8N_FILESYSTEM_BINARY_DATA_FOLDER=/files/binary
      - NODE_OPTIONS=--max-old-space-size=4096
      - N8N_CONCURRENCY=2
      - TZ=${GENERIC_TIMEZONE}
      - GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
      - N8N_TRUSTED_PROXIES=172.18.0.0/16
      - N8N_SECURITY_TRUSTED_PROXIES=172.18.0.0/16
      - N8N_RATE_LIMITS_DISABLED=true
    mem_limit: 3g
    volumes:
      - n8n_data:/home/node/.n8n
      - ./local-files:/files
      - /root/output:/data/output:rw

volumes:
  traefik_data:
  n8n_data:
EOF

    mkdir -p local-files
    mkdir -p custom
    cat > custom/Dockerfile << 'EOF'
FROM n8nio/n8n:latest
EOF

    if [ -f "docker-compose.yml" ] && [ -f ".env" ]; then
        print_success "Файлы .env и docker-compose.yml созданы"
        if docker compose config --quiet 2>/dev/null; then
            print_success "Синтаксис docker-compose.yml корректен"
        else
            print_warning "Не удалось проверить docker-compose.yml. Убедитесь, что Docker Compose установлен."
        fi
    else
        print_error "Не удалось создать конфигурационные файлы"
        exit 1
    fi

    cd "$ORIGINAL_DIR" || true
}

check_config_files() {
    print_info "Проверка конфигурационных файлов..."

    if [ ! -f "docker-compose.yml" ]; then
        print_error "Файл docker-compose.yml не найден"
        return 1
    fi

    if ! docker compose config --quiet 2>/dev/null; then
        print_error "Ошибка в синтаксисе docker-compose.yml"
        return 1
    fi

    if [ ! -f ".env" ]; then
        print_error "Файл .env не найден"
        return 1
    fi

    print_success "Конфигурационные файлы корректны"
    return 0
}

start_services() {
    print_header "Запуск сервисов n8n"

    if [ ! -d "$PROJECT_DIR" ]; then
        print_error "Директория $PROJECT_DIR не найдена"
        exit 1
    fi

    cd "$PROJECT_DIR"

    if ! check_config_files; then
        exit 1
    fi

    print_info "Запуск Docker Compose..."
    docker compose up -d

    print_info "Ожидание запуска сервисов..."
    sleep 10

    if docker compose ps | grep -q "Up"; then
        print_success "Сервисы успешно запущены!"

        EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || echo "не удалось определить")

        print_header "Информация о развертывании"
        echo -e "${GREEN}✓ n8n доступен по адресу: https://${SUBDOMAIN}.${MAIN_DOMAIN}${NC}"
        echo -e "${GREEN}✓ Traefik dashboard: https://traefik.${MAIN_DOMAIN}${NC}"
        echo -e "${BLUE}ℹ Внешний IP сервера: $EXTERNAL_IP${NC}"
        echo -e "${YELLOW}⚠ Убедитесь, что DNS записи указывают на этот IP${NC}"
        echo -e "${YELLOW}⚠ Данные для входа: ${SSL_EMAIL} / (указанный пароль)${NC}"
    else
        print_error "Ошибка запуска сервисов"
        docker compose logs
        exit 1
    fi

    cd "$ORIGINAL_DIR" || true
}

setup_autostart() {
    print_header "Настройка автозапуска"

    cat > /etc/systemd/system/n8n.service << EOF
[Unit]
Description=n8n Workflow Automation
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$ORIGINAL_DIR/$PROJECT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable n8n
    if systemctl start n8n 2>/dev/null; then
        print_success "Сервис n8n запущен"
    else
        print_warning "Не удалось автоматически запустить сервис n8n. Проверьте journalctl -u n8n"
    fi

    print_success "Автозапуск настроен"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Скрипт должен быть запущен с правами root (sudo)"
        exit 1
    fi

    print_header "Установка n8n (пользовательский скрипт)"
    print_info "Скрипт поддерживает Ubuntu 20.04, 22.04, 24.04 LTS"

    ORIGINAL_DIR=$(pwd)

    check_ubuntu_version
    install_docker
    gather_user_input
    create_config_files
    start_services
    setup_autostart

    print_header "Установка завершена"
    print_success "n8n успешно развернут"
    print_info "Если нужно изменить данные для входа, обновите .env и выполните docker compose up -d"
}

case "${1:-}" in
    --help|-h)
        echo "Скрипт для автоматической установки n8n"
        echo "Запросит только домен, email и пароль"
        echo "Использование: $0 [опции]"
        echo "  --help        Показать справку"
        echo "  --update      Обновить контейнеры n8n"
        echo "  --stop        Остановить n8n"
        echo "  --restart     Перезапустить n8n"
        echo "  --check       Проверить конфигурацию"
        exit 0
        ;;
    --update)
        print_header "Обновление n8n"
        ORIGINAL_DIR=$(pwd)
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            if [ ! -f "docker-compose.yml" ]; then
                print_error "docker-compose.yml не найден"
                exit 1
            fi
            docker compose pull
            docker compose up -d
            print_success "n8n обновлен"
        else
            print_error "Директория $PROJECT_DIR не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" || true
        ;;
    --stop)
        print_header "Остановка n8n"
        ORIGINAL_DIR=$(pwd)
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            if [ ! -f "docker-compose.yml" ]; then
                print_error "docker-compose.yml не найден"
                exit 1
            fi
            docker compose down
            print_success "n8n остановлен"
        else
            print_error "Директория $PROJECT_DIR не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" || true
        ;;
    --restart)
        print_header "Перезапуск n8n"
        ORIGINAL_DIR=$(pwd)
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            if [ ! -f "docker-compose.yml" ]; then
                print_error "docker-compose.yml не найден"
                exit 1
            fi
            docker compose restart
            print_success "n8n перезапущен"
        else
            print_error "Директория $PROJECT_DIR не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" || true
        ;;
    --check)
        print_header "Проверка конфигурации"
        ORIGINAL_DIR=$(pwd)
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            if check_config_files; then
                print_success "Конфигурация корректна"
            else
                exit 1
            fi
        else
            print_error "Директория $PROJECT_DIR не найдена"
            exit 1
        fi
        cd "$ORIGINAL_DIR" || true
        ;;
    *)
        main
        ;;
esac
