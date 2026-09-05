# Makefile
.PHONY: help up down logs clean build test

help:
	@echo "Comandos disponibles:"
	@echo "  make up           - Levantar todos los servicios"
	@echo "  make down         - Detener todos los servicios"
	@echo "  make logs         - Ver logs de todos los servicios"
	@echo "  make clean        - Limpiar containers, volumes y datos"
	@echo "  make build        - Construir todas las imágenes"
	@echo "  make test         - Ejecutar todos los tests"
	@echo "  make dev          - Levantar en modo desarrollo con hot-reload"
	@echo "  make prod         - Levantar en modo producción"
	@echo "  make dev-tools    - Levantar herramientas de desarrollo (pgAdmin, Redis Commander)"
	@echo "  make migrate      - Ejecutar migraciones de base de datos"
	@echo "  make seed         - Seedear base de datos con datos de ejemplo"

up:
	docker-compose up -d

down:
	docker-compose down

logs:
	docker-compose logs -f

clean:
	docker-compose down -v
	docker system prune -f

build:
	docker-compose build

dev:
	docker-compose -f docker-compose.yml up -d

prod:
	docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

dev-tools:
	docker-compose --profile dev-tools up -d

migrate:
	docker-compose exec backend-express npm run migrate

seed:
	docker-compose exec backend-express npm run seed