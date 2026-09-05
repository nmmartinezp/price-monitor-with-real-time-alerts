FROM golang:1.21-alpine

WORKDIR /app

# Instalar herramientas de desarrollo
RUN go install github.com/air-verse/air@latest

# Copiar go.mod y go.sum
COPY go.mod go.sum ./
RUN go mod download

# Copiar el resto del código
COPY . .

EXPOSE 8080

CMD ["air", "-c", ".air.toml"]