# Specifikacija za backend: dodjela smjene PO DANU (po datumu)

> Prompt/specifikacija za backend developera (Spring Boot). Cilj: omogućiti
> dodjelu smjene zaposlenom **za konkretan datum** (a ne samo za cijelu sedmicu),
> uz izmjenu/uklanjanje po pojedinačnom danu. Time se dobija mjesečni kalendar u
> kojem admin bira barbera → čekira pojedinačne dane → dodijeli/izmijeni smjenu
> baš tim danima.

---

## 1. Kontekst (postojeće stanje)

Već postoji **sedmična** dodjela smjene:
- `POST/PUT /api/shift-assignments` sa `{ employeeId, shiftTemplateId, weekStartDate (MORA biti ponedjeljak) }`.
- `GET /api/shift-assignments?from&to` → dodjele po sedmici.
- Šablon (`shift-templates`) definiše radne sate PO DANU U SEDMICI (Pon–Ned).

**Ograničenje:** jedan zaposleni može imati samo JEDAN šablon za cijelu sedmicu —
ne mogu se dati različite smjene za pojedinačne dane iste sedmice. Ova
specifikacija dodaje **novi resurs: smjena po DATUMU**, koji ima **prednost** nad
sedmičnom dodjelom za taj datum.

Konvencije (kao i ostatak API-ja):
- Vrijeme = `"HH:mm:ss"`, datum = `"YYYY-MM-DD"`.
- `sellingPlaceId` se izvodi **iz JWT-a na serveru** — klijent ga ne šalje.
- Upravljanje: **samo ADMIN** (u suprotnom `403 ACCESS_DENIED`).
- Error envelope: `{ code, message, details }` (`VALIDATION_FAILED`, `NOT_FOUND`, `ACCESS_DENIED`).

---

## 2. Novi model (entitet + tabela)

Entitet: **`EmployeeShiftDay`** (smjena zaposlenog za jedan datum).

Tabela `employee_shift_day`:

| kolona             | tip              | napomena                                          |
|--------------------|------------------|---------------------------------------------------|
| `id`               | PK (bigint)      |                                                   |
| `selling_place_id` | FK               | iz JWT-a; ne dolazi od klijenta                   |
| `employee_id`      | FK               | zaposleni kome se dodjeljuje                       |
| `date`             | DATE             | konkretan datum smjene                            |
| `start_time`       | TIME             | početak smjene tog dana                           |
| `end_time`         | TIME             | kraj smjene tog dana (mora biti > start_time)     |
| `shift_template_id`| FK NULL          | opciono — samo radi naziva/labela (npr. „Rana")   |
| `note`             | VARCHAR(255) NULL| opciono                                           |

**Jedinstveno ograničenje:** `UNIQUE (employee_id, date)` — jedan zaposleni ima
najviše JEDNU smjenu po danu (upsert po datumu).

> Napomena o `shift_template_id`: **izvor istine za sate je `start_time`/`end_time`**
> (frontend ih pošalje). `shift_template_id` je samo referenca za naziv smjene u
> prikazu; može biti `null` (kad admin unese proizvoljno vrijeme).

### DTO oblici

`ShiftDayRequest` (ulaz):
```json
{
  "employeeId": 7,
  "date": "2026-08-12",
  "startTime": "08:00:00",
  "endTime": "14:00:00",
  "shiftTemplateId": 3,
  "note": null
}
```

`ShiftDayResponse` (izlaz):
```json
{
  "id": 55,
  "sellingPlaceId": 1,
  "employeeId": 7,
  "employeeName": "Marko",
  "date": "2026-08-12",
  "startTime": "08:00:00",
  "endTime": "14:00:00",
  "shiftTemplateId": 3,
  "shiftTemplateName": "Rana",
  "note": null
}
```

---

## 3. Endpointi (svi ADMIN-only, `sellingPlaceId` iz JWT-a)

### 3.1 Pregled smjena za opseg datuma (za kalendar)
```
GET /api/shift-days?from=YYYY-MM-DD&to=YYYY-MM-DD&employeeId={opciono}
```
- Vrati `List<ShiftDayResponse>` za sve datume u opsegu `[from, to]` (uključivo).
- Bez `employeeId` → vrati za **sve zaposlene** (za mjesečni kalendar svih barbera).
- Sa `employeeId` → filtriraj na tog zaposlenog.

### 3.2 Grupni upis/izmjena (bulk upsert)
```
PUT /api/shift-days
Body: List<ShiftDayRequest>
```
- Za svaku stavku: ako smjena za `(employeeId, date)` **postoji → izmijeni**
  (start/end/template/note), u suprotnom **kreiraj**.
- **NE briše** datume kojih nema u tijelu (parcijalni upsert).
- Vrati `List<ShiftDayResponse>` za upisane datume.
- Ovim frontend jednim pozivom: dodijeli smjenu za više izabranih dana, ILI
  izmijeni jedan dan.

### 3.3 Uklanjanje smjene za jedan dan
```
DELETE /api/shift-days?employeeId={id}&date=YYYY-MM-DD
```
- Ukloni smjenu tog zaposlenog za taj datum → taj dan postaje slobodan (ili se
  vraća na sedmičnu dodjelu ako postoji — vidi tačku 4).
- `204 No Content`; ako ne postoji → `404 NOT_FOUND`.

### 3.4 (Opciono) Grupno uklanjanje
```
DELETE /api/shift-days?employeeId={id}&from=YYYY-MM-DD&to=YYYY-MM-DD
```
- Obriši sve smjene tog zaposlenog u opsegu. Nije obavezno.

---

## 4. NAJVAŽNIJE: integracija sa `/api/schedule`

Već postoji:
```
GET /api/schedule?employeeId=&from=YYYY-MM-DD&to=YYYY-MM-DD
→ List<ScheduleDayResponse> { date, dayOfWeek, salonOpensAt, salonClosesAt,
                              shiftStart, shiftEnd, shiftTemplateId, shiftTemplateName }
```

Za `shiftStart` / `shiftEnd` / `shiftTemplateName` na dati datum primijeni ovaj
**redoslijed prednosti**:

1. Ako postoji **smjena po datumu** (`employee_shift_day`) za `(employeeId, date)` →
   koristi njen `start_time`/`end_time` (+ naziv iz `shift_template_id` ako ga ima).
2. Inače, ako postoji **sedmična dodjela** za tu sedmicu → kao i sada: sati iz
   šablona za taj dan u sedmici.
3. Inače → slobodan dan (`shiftStart`/`shiftEnd` = `null`).

Time cijela aplikacija (kalendar termina, upozorenja pri zakazivanju) **automatski**
poštuje smjene po danu, bez dodatnog rada na frontendu.

---

## 5. Validacija

- `employeeId` — obavezno, mora postojati (i pripadati istom `sellingPlaceId`).
- `date` — obavezno, `YYYY-MM-DD`.
- `startTime`, `endTime` — obavezni `"HH:mm:ss"`, i mora biti `endTime > startTime`
  → u suprotnom `400 VALIDATION_FAILED`.
- `shiftTemplateId` — opciono; ako je zadat, mora postojati.
- U jednom `PUT` tijelu **ne smiju** postojati dvije iste kombinacije
  `(employeeId, date)` → `400 VALIDATION_FAILED`.
- `note` — opciono, max 255.

## 6. Sigurnost

- Svi endpointi: **ADMIN**; u suprotnom `403 ACCESS_DENIED`.
- `sellingPlaceId` uvijek iz JWT-a; nema pristupa tuđem prodajnom mjestu.

---

## 7. Sažetak (checklist za developera)

- [ ] Entitet + tabela `employee_shift_day` sa `UNIQUE(employee_id, date)`.
- [ ] `GET /api/shift-days?from&to&employeeId?`
- [ ] `PUT /api/shift-days` (bulk upsert po `employeeId`+`date`)
- [ ] `DELETE /api/shift-days?employeeId&date`
- [ ] (opciono) `DELETE /api/shift-days?employeeId&from&to`
- [ ] **`/api/schedule` primjenjuje smjene po danu** (tačka 4) — obavezno.
- [ ] Validacija (tačka 5), ADMIN-only, `sellingPlaceId` iz JWT-a.

> Odnos prema starom `/api/shift-assignments`: ostaje netaknut (sedmična dodjela i
> dalje radi kao „default"). Nova dodjela po danu ima prednost. Frontendski novi
> kalendar koristi isključivo `/api/shift-days`.
