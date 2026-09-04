# Price Monitor With Real Time Alerts

Problem:

Users want to track the prices of products such as those on Amazon or MercadoLibre and receive alerts when they drop below a certain price.

Solution:

- Scheduled scraping system (every 6–12 hours)
- Email/Telegram alerts for price drops
- Price history with charts
- Management of products to monitor (CRUD)
- Webhook for Zapier/Make integration

## General System architecture

<div style="width: 100%;" align="center">
<image src="docs/arqdiagram.png" style="width: 100%;"/></div>

### Main Worflow

<div style="width: 100%;" align="center">
<image src="docs/mainflow.png" style="width: 50%;"/></div>
