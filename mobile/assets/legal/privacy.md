# SafeHer — Privacy Policy

**Version: 2026-10-06**

> ## ⚠️ PLACEHOLDER — NOT LEGAL ADVICE, NOT REVIEWED BY A LAWYER
>
> This document was written by the engineering team to describe, accurately,
> what the software actually does with data. It is **not** a legally
> sufficient privacy policy and must not be published as one.
>
> It has **not** been reviewed by a qualified legal professional, and it has
> not been assessed against the DPDP Act 2023 (India), GDPR, or any other
> regime. A lawyer needs to review it before SafeHer is offered to real users.
>
> What it is good for: it is a truthful engineering description, so the lawyer
> reviewing it is working from facts rather than intentions.

---

## What this app is

SafeHer is a personal safety application. It pairs with two wearables — a glove
and a pair of glasses — and can raise an alarm to contacts you nominate.

To do that it touches some of the most sensitive data a phone holds: where you
are, what you say, what your camera sees, and who you would call for help. This
document sets out exactly what is collected, why, where it goes, and what is
*not* collected.

## Data inventory

| Data | Why | Where it is stored | Who can reach it | Retention |
|---|---|---|---|---|
| Email, name, phone | Your account, and contacting you | SafeHer database | You; the service operator | Until deletion |
| Password | Sign-in | Database, **hashed** (PBKDF2) | Nobody — the plaintext is never stored | Until deletion |
| **Location (GPS)** | Attached to an alert so contacts know where to go; breadcrumbs during a Safe Journey | Database | You; the people you nominate, when an alert fires | Until deletion |
| **Phone microphone** | Recognising spoken distress | **Not stored.** Speech is transcribed on your phone, scored, and the words discarded | Nobody — only a number leaves the device | Not retained |
| **Glasses microphone** | Evidence during an emergency | Encrypted blob storage | You | Until deletion |
| **Glasses camera** | Detecting a weapon | **Video is not uploaded.** Frames are scored on your phone | Nobody — only a score leaves the device | Not retained |
| **Glove sensors** | Detecting a fall or force | Score only, with the incident | You | Until deletion |
| **Heart rate** | Context on an incident report | Database, with the incident | You | Until deletion |
| Emergency contacts | Who to alert | Database | You; each contact learns they were contacted | Until deletion |
| Incident evidence | Your record of what happened | Encrypted, private bucket | You, through an authenticated request | Until deletion |

## Three things worth stating plainly

**Your camera's video never leaves your phone.** Weapon detection runs on the
device. What is sent onward is a single number between 0 and 1.

**What you say is not recorded for threat detection.** The phone's speech
recogniser turns speech into text on the device, a classifier scores the text,
and both the audio and the text are discarded. Only the score is sent. The
glasses microphone is different — during an emergency it *is* recorded, as
evidence, and that recording is uploaded with the incident.

**Evidence is encrypted before it is stored**, kept in a private bucket, and
served only through an authenticated request that checks you own the incident.
There are no shareable links; changing an ID in a URL returns "not found".

## When detection runs

Continuous detection runs **only during a Safe Journey you have started**. The
microphone and glove run for its duration; the camera is opened only when
something suggests it is needed, and closed again after about 45 seconds.

Outside a journey, no automatic detection runs.

## What we do not do

- We do not sell data.
- We do not use your data to train models. The models shipped with the app were
  trained on public datasets and synthetic recordings.
- We do not share your location with anyone except the contacts you nominate,
  and only when an alert fires.

## Your choices

- **See it** — your incidents and evidence are in the app.
- **Delete it** — Settings → Delete Account removes your data. Deletion runs
  after a short grace period, so an accidental deletion can be reversed.
- **Turn parts off** — location sharing, notifications and the shake trigger
  are individually switchable in Settings.
- **Remove a device** — unpairing stops its data reaching the app.

## Contact

**TO BE COMPLETED** — a real contact address and a data controller identity are
legally required and must be filled in before release.

---

*Questions this document does not yet answer, and a lawyer must: the legal
basis for processing, the data controller's identity, international transfer
terms (the database and object storage may sit outside your country),
breach-notification commitments, and the precise retention period after
deletion.*
