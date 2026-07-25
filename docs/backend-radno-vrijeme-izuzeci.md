# Specifikacija za backend: izuzeci radnog vremena po datumu

> Prompt/specifikacija za backend developera (Spring Boot). Cilj: omogućiti da
> salon ima **radno vrijeme po konkretnom datumu**, a ne samo stalni sedmični
> šablon. Time se pokrivaju dva zahtjeva:
> 1. ručno označiti **pojedinačne neradne datume** (praznici / vanredna zatvaranja) za cio mjesec;
> 2. **različiti radni sati za različite kalendarske sedmice** (npr. jedna sedmica u avgustu jedni sati, sljedeća drugi).

---

## 1. Kontekst (postojeće stanje — NE mijenjati)

Već postoji **sedmični** šablon radnog vremena salona:

- `GET /api/working-hours` → `List<WorkingHoursResponse>` = `{ id, sellingPlaceId, dayOfWeek (MONDAY..SUNDAY), opensAt "HH:mm:ss", closesAt "HH:mm:ss" }`
- `PUT /api/working-hours` → zamjena cijele sedmice.

Taj šablon ostaje **osnova** (default) — isti je svake sedmice. Novi resurs u ovoj
specifikaciji su **izuzeci vezani za konkretan datum**, koji **imaju prednost** nad
sedmičnim šablonom za taj datum.

Konvencije koje treba poštovati (kao i ostatak API-ja):
- Vrijeme = string `"HH:mm:ss"`, datum = string `"YYYY-MM-DD"`.
- `sellingPlaceId` se **izvodi iz JWT-a na serveru** — klijent ga NIKAD ne šalje.
- Upravljanje je **samo za ADMIN** (u suprotnom `403 ACCESS_DENIED`).
- Error envelope kao i drugdje: `{ code, message, details }` sa kodovima
  `VALIDATION_FAILED`, `ACCESS_DENIED`, `NOT_FOUND`.

---

## 2. Novi model (entitet + tabela)

Entitet: **`WorkingHoursOverride`** (izuzetak radnog vremena za jedan datum).

Tabela `working_hours_override`:

| kolona            | tip           | napomena                                             |
|-------------------|---------------|------------------------------------------------------|
| `id`              | PK (bigint)   |                                                      |
| `selling_place_id`| FK            | iz JWT-a; ne dolazi od klijenta                      |
| `date`            | DATE          | konkretan datum izuzetka                             |
| `closed`          | BOOLEAN       | `true` = salon zatvoren tog datuma                   |
| `opens_at`        | TIME NULL     | obavezno ako `closed=false`; ignoriše se ako `closed=true` |
| `closes_at`       | TIME NULL     | obavezno ako `closed=false`                          |
| `note`            | VARCHAR(255) NULL | opciono (npr. "Praznik", "Inventura")           |

**Jedinstveno ograničenje:** `UNIQUE (selling_place_id, date)` — najviše jedan
izuzetak po danu po prodajnom mjestu (upsert po datumu).

### DTO oblici

`WorkingHoursOverrideRequest` (ulaz):
```json
{
  "date": "2026-08-15",
  "closed": true,
  "opensAt": null,
  "closesAt": null,
  "note": "Praznik"
}
```
```json
{
  "date": "2026-08-10",
  "closed": false,
  "opensAt": "10:00:00",
  "closesAt": "16:00:00",
  "note": null
}
```

`WorkingHoursOverrideResponse` (izlaz) — kao request + `id` i `sellingPlaceId`:
```json
{
  "id": 42,
  "sellingPlaceId": 1,
  "date": "2026-08-15",
  "closed": true,
  "opensAt": null,
  "closesAt": null,
  "note": "Praznik"
}
```

---

## 3. Endpointi (svi ADMIN-only, `sellingPlaceId` iz JWT-a)

### 3.1 Pregled izuzetaka za opseg datuma
```
GET /api/working-hours/overrides?from=YYYY-MM-DD&to=YYYY-MM-DD
```
- Vrati `List<WorkingHoursOverrideResponse>` za sve datume u opsegu `[from, to]`
  (uključivo) za salon iz JWT-a.
- Koristi frontend da iscrta mjesečni kalendar.

### 3.2 Grupno upisivanje/izmjena (bulk upsert)
```
PUT /api/working-hours/overrides
Body: List<WorkingHoursOverrideRequest>
```
- Za svaku stavku: ako izuzetak za taj `date` (i `sellingPlaceId` iz JWT-a)
  **već postoji → izmijeni ga**, u suprotnom **kreiraj novi**.
- **NE briše** datume kojih nema u tijelu (parcijalni upsert).
- Vrati `List<WorkingHoursOverrideResponse>` za upisane datume.
- Razlog: frontend jednim pozivom pošalje cijelu sedmicu/mjesec (npr. „označi
  sve nedjelje kao neradne" ili „ova sedmica 10–16h").

### 3.3 Brisanje izuzetka za jedan datum
```
DELETE /api/working-hours/overrides/{date}     // date = YYYY-MM-DD
```
- Ukloni izuzetak za taj datum → datum se vraća na **sedmični šablon**.
- `204 No Content`; ako ne postoji → `404 NOT_FOUND`.

### 3.4 (Opciono, zgodno) Grupno brisanje za opseg
```
DELETE /api/working-hours/overrides?from=YYYY-MM-DD&to=YYYY-MM-DD
```
- Obriši sve izuzetke u opsegu. Nije obavezno, ali olakšava „očisti mjesec".

---

## 4. NAJVAŽNIJE: integracija sa `/api/schedule`

Već postoji:
```
GET /api/schedule?employeeId=&from=YYYY-MM-DD&to=YYYY-MM-DD
→ List<ScheduleDayResponse> { date, dayOfWeek, salonOpensAt, salonClosesAt, shiftStart, shiftEnd, shiftTemplateId, shiftTemplateName }
```

Ovaj endpoint **mora da uzme u obzir izuzetke** pri računanju `salonOpensAt` /
`salonClosesAt` za svaki dan:

1. Ako za `date` postoji izuzetak i `closed = true` → `salonOpensAt = null`,
   `salonClosesAt = null` (salon zatvoren tog dana).
2. Ako postoji izuzetak i `closed = false` → `salonOpensAt = opensAt`,
   `salonClosesAt = closesAt` iz izuzetka.
3. Ako izuzetka nema → kao i sada: uzmi iz sedmičnog šablona
   (`/api/working-hours` po `dayOfWeek`).

Time cijela aplikacija (kalendar termina, upozorenja pri zakazivanju) **automatski
poštuje** zatvorene dane i posebne sate — bez dodatnog rada na frontendu.

---

## 5. Validacija

- `date` — obavezno, format `YYYY-MM-DD`.
- `closed` — obavezno (boolean).
- Ako `closed = false`: `opensAt` i `closesAt` su **obavezni** i mora biti
  `closesAt > opensAt`; u suprotnom `400 VALIDATION_FAILED`.
- Ako `closed = true`: `opensAt`/`closesAt` se ignorišu (ili moraju biti `null`).
- U jednom `PUT` tijelu **ne smiju** postojati dva ista datuma → `400 VALIDATION_FAILED`.
- `note` — opciono, max 255 znakova.

## 6. Sigurnost

- Svi endpointi: **ADMIN**; u suprotnom `403 ACCESS_DENIED`.
- `sellingPlaceId` uvijek iz JWT-a; klijent ga ne šalje i ne može da čita/piše
  tuđe prodajno mjesto.

---

## 7. Sažetak zahtjeva (checklist za developera)

- [ ] Entitet + tabela `working_hours_override` sa `UNIQUE(selling_place_id, date)`.
- [ ] `GET /api/working-hours/overrides?from&to`
- [ ] `PUT /api/working-hours/overrides` (bulk upsert po datumu)
- [ ] `DELETE /api/working-hours/overrides/{date}`
- [ ] (opciono) `DELETE /api/working-hours/overrides?from&to`
- [ ] **`/api/schedule` primjenjuje izuzetke** (tačka 4) — obavezno.
- [ ] Validacija (tačka 5), ADMIN-only, `sellingPlaceId` iz JWT-a.

> Napomena: model podržava JEDAN interval (otvaranje–zatvaranje) po danu, kao i
> postojeći sedmični šablon. Ako će ikad trebati podijeljeno radno vrijeme
> (npr. 08–12 i 16–20), to je zasebno proširenje i nije dio ove specifikacije.
