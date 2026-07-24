# SSL/TLS Certificates

This directory should contain SSL certificates for secure communication.

## Development (Self-Signed Certificates)

Generate self-signed certificates for development:

```bash
# Generate CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt \
  -subj "/C=US/ST=State/L=City/O=SafeHer/CN=SafeHer CA"

# Generate server certificate
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/ST=State/L=City/O=SafeHer/CN=localhost"

# Sign server certificate
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out server.crt

# Generate client certificate (for device authentication)
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr \
  -subj "/C=US/ST=State/L=City/O=SafeHer/CN=client"
openssl x509 -req -days 365 -in client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out client.crt

# Cleanup CSR files
rm *.csr
```

## Production

For production, use certificates from a trusted Certificate Authority:

### Option 1: Let's Encrypt (Free)
```bash
certbot certonly --standalone -d safeher.com -d www.safeher.com
# Certificates will be in: /etc/letsencrypt/live/safeher.com/
```

### Option 2: Commercial CA
Purchase certificates from providers like:
- DigiCert
- Sectigo
- GoDaddy
- Namecheap

## Required Files

- `ca.crt` - Certificate Authority certificate
- `server.crt` - Server certificate
- `server.key` - Server private key
- `client.crt` - Client certificate (optional, for mutual TLS)
- `client.key` - Client private key (optional)

## Permissions

Ensure proper permissions:
```bash
chmod 600 *.key
chmod 644 *.crt
```

## Docker Volume Mounting

These certificates are mounted in:
- MQTT Broker: `/mosquitto/config/ssl/`
- Nginx: `/etc/nginx/ssl/`

## Security Notes

- **Never commit private keys (.key files) to version control**
- Add `*.key` to `.gitignore`
- Rotate certificates before expiration
- Use strong key sizes (4096 bits for RSA)
- Keep CA private key secure
