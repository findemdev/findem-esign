# Findem Sign

Findem's e-signature service: a fork of [DocuSeal](https://github.com/docusealco/docuseal) (AGPL-3.0) that presents itself as Findem where people meet it. The People gateway in Findem Studio sends documents through its API; signers sign on its hosted page. Changes against upstream are limited to the product name and addresses (`lib/docuseal.rb`), the mark and icons, the page titles and metadata, and the signing page's credit, which links to this repository as the licence's source offer. Everything else, including the licence, is upstream's; merge upstream tags to pick up fixes.

**Platform accounts.** A shared, multi-tenant instance (`MULTITENANT=true`) lets the platform that runs it create tenant accounts without anyone signing up: `POST /api/platform/accounts` with `Authorization: Bearer <PLATFORM_API_TOKEN>` and a JSON body `{ external_id, name, email, timezone, locale, webhook: { url, secret: { "X-Header": "value" }, events } }` creates the account (or finds it by `external_id`), an admin user with the given email and a random password, an API token and the webhook, and answers `201 { account_id, user_id, api_token }`; the same call again answers `200` with a freshly rotated token (the previous one stops working) and the webhook upserted; invalid input is a `422` with a short `error`. The route does not exist (`404`) unless `PLATFORM_API_TOKEN` is set. Public sign-up (`/sign_up`) stays closed on a multi-tenant instance unless `ALLOW_SIGNUP=true`, and a multi-tenant instance has no first-run setup (`/setup` answers 404 and visitors meet the sign-in page); a single-tenant instance keeps both as upstream has them. The platform's user stands for the tenant: it carries the account's name, so emails to signers show the tenant as the sender; it gets no completed or declined notices (the platform hears of those by webhook); and a platform account's users get no password-reset or unlock emails, so nobody signs in to them by email.

**Templates from a PDF.** Accounts nobody signs into get their templates through the API: `POST /api/templates/pdf` with the account's `X-Auth-Token` and `{ name, external_id?, folder_name?, roles?: ["Employee", …], detect_fields?, documents: [{ name?, file: <base64 PDF>, fields?: [{ name, type, role?, required?, readonly?, default_value?, options?, preferences?, areas: [{ x, y, w, h, page, option? }] }] }] }` answers the template as `GET /api/templates/:id` does. `roles` are the signers in order (one "First Party" by default). A document's fields are the ones placed in the request (areas are fractions of the page's width and height from its top-left corner; `page` counts from 1); without them, the PDF's own form fields; without those and with `detect_fields: true`, the fields the field detection finds on its pages. Fields without a role, and every form or detected field, belong to the first role. Invalid input is a `422` with a short `error` and creates nothing.

**Platform sign-in.** People signed in on the platform that runs a shared instance open their tenant's account without a password. The platform sends them to `GET /platform/session?token=<jws>&next=<path>`: a single-use, 60-second HS256 token under `HMAC-SHA256(PLATFORM_API_TOKEN, "findem-sign/session/v1")`, with `aud: "findem-sign-session"`, `tenant` (the account's `external_id`), `email`, `name`, `sub`, `iat`, `exp` and `jti`. A valid token signs the person in, in a fresh session, as the account's user with that email (an administrator is created on first use), and lands on `next`, a path on this site. An expired, reused or forged token, an unknown tenant, or an email that belongs to another account gets a page that sends them back. With `PLATFORM_API_TOKEN` set, the sign-in page also offers "Sign in with Findem Studio", which starts at `PLATFORM_SIGN_IN_URL`.

---

<h1 align="center" style="border-bottom: none">
  <div>
    <a href="https://www.docuseal.com">
      <img  alt="DocuSeal" src="https://github.com/user-attachments/assets/38b45682-ffa4-4919-abde-d2d422325c44" width="80" />
      <br>
    </a>
    DocuSeal
  </div>
</h1>
<h3 align="center">
  Open source document filling and signing
</h3>
<p align="center">
  <a href="https://hub.docker.com/r/docuseal/docuseal">
    <img alt="Docker releases" src="https://img.shields.io/docker/v/docuseal/docuseal">
  </a>
  <a href="https://discord.gg/qygYCDGck9">
    <img src="https://img.shields.io/discord/1125112641170448454?logo=discord"/>
  </a>
  <a href="https://twitter.com/intent/follow?screen_name=docusealco">
    <img src="https://img.shields.io/twitter/follow/docusealco?style=social" alt="Follow @docusealco" />
  </a>
</p>
<p>
DocuSeal is an open source platform that provides secure and efficient digital document signing and processing. Create PDF forms to have them filled and signed online on any device with an easy-to-use, mobile-optimized web tool.
</p>
<h2 align="center">
  <a href="https://demo.docuseal.tech">✨ Live Demo</a>
  <span>|</span>
  <a href="https://docuseal.com/sign_up">☁️ Try in Cloud</a>
</h2>

[![Demo](https://github.com/docusealco/docuseal/assets/5418788/d8703ea3-361a-423f-8bfe-eff1bd9dbe14)](https://demo.docuseal.tech)

## Features
- PDF form fields builder (WYSIWYG)
- 12 field types available (Signature, Date, File, Checkbox etc.)
- Multiple submitters per document
- Automated emails via SMTP
- Files storage on disk or AWS S3, Google Storage, Azure Cloud
- Automatic PDF eSignature
- PDF signature verification
- User management
- Mobile-optimized
- 7 UI languages with signing available in 14 languages
- API and Webhooks for integrations
- Easy to deploy in minutes

## Pro Features
- Company logo and white-label
- User roles
- Automated reminders
- Invitation and identity verification via SMS
- Conditional fields and formulas
- Bulk send with CSV, XLSX spreadsheet import
- SSO / SAML
- Template creation with HTML API ([Guide](https://www.docuseal.com/guides/create-pdf-document-fillable-form-with-html-api))
- Template creation with PDF or DOCX and field tags API ([Guide](https://www.docuseal.com/guides/use-embedded-text-field-tags-in-the-pdf-to-create-a-fillable-form))
- Embedded signing form ([React](https://github.com/docusealco/docuseal-react), [Vue](https://github.com/docusealco/docuseal-vue), [Angular](https://github.com/docusealco/docuseal-angular) or [JavaScript](https://www.docuseal.com/docs/embedded))
- Embedded document form builder ([React](https://github.com/docusealco/docuseal-react), [Vue](https://github.com/docusealco/docuseal-vue), [Angular](https://github.com/docusealco/docuseal-angular) or [JavaScript](https://www.docuseal.com/docs/embedded))
- [Learn more](https://www.docuseal.com/pricing)

## Deploy

|Heroku|Railway|
|:--:|:---:|
| [<img alt="Deploy on Heroku" src="https://www.herokucdn.com/deploy/button.svg" height="40">](https://heroku.com/deploy?template=https://github.com/docusealco/docuseal-heroku) | [<img alt="Deploy on Railway" src="https://railway.app/button.svg" height="40">](https://railway.com/deploy/IGoDnc?referralCode=ruU7JR)|
|**DigitalOcean**|**Render**|
| [<img alt="Deploy on DigitalOcean" src="https://www.deploytodo.com/do-btn-blue.svg" height="40">](https://cloud.digitalocean.com/apps/new?repo=https://github.com/docusealco/docuseal-digitalocean/tree/master&refcode=421d50f53990) | [<img alt="Deploy to Render" src="https://render.com/images/deploy-to-render-button.svg" height="40">](https://render.com/deploy?repo=https://github.com/docusealco/docuseal-render)

#### Docker

```sh
docker run --name docuseal -p 3000:3000 -v.:/data docuseal/docuseal
```

By default DocuSeal docker container uses an SQLite database to store data and configurations. Alternatively, it is possible to use PostgreSQL or MySQL databases by specifying the `DATABASE_URL` env variable.

#### Docker Compose

Download docker-compose.yml into your private server:
```sh
curl https://raw.githubusercontent.com/docusealco/docuseal/master/docker-compose.yml > docker-compose.yml
```

Run the app under a custom domain over https using docker compose (make sure your DNS points to the server to automatically issue ssl certs with Caddy):
```sh
sudo HOST=your-domain-name.com docker compose up
```

## For Businesses
### Integrate seamless document signing into your web or mobile apps with DocuSeal

At DocuSeal we have expertise and technologies to make documents creation, filling, signing and processing seamlessly integrated with your product. We specialize in working with various industries, including **Banking, Healthcare, Transport, Real Estate, eCommerce, KYC, CRM, and other software products** that require bulk document signing. By leveraging DocuSeal, we can assist in reducing the overall cost of developing and processing electronic documents while ensuring security and compliance with local electronic document laws.

[Book a Meeting](https://www.docuseal.com/contact)

## License

Distributed under the AGPLv3 License with Section 7(b) Additional Terms. See [LICENSE](https://github.com/docusealco/docuseal/blob/master/LICENSE) and [LICENSE_ADDITIONAL_TERMS](https://github.com/docusealco/docuseal/blob/master/LICENSE_ADDITIONAL_TERMS) for more information.
Unless otherwise noted, all files © 2023-2026 DocuSeal LLC.

## Tools

- [Signature Maker](https://www.docuseal.com/online-signature)
- [Sign Document Online](https://www.docuseal.com/sign-documents-online)
- [Fill PDF Online](https://www.docuseal.com/fill-pdf)
