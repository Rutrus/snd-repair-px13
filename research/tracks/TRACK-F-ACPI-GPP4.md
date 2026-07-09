# TRACK F — ACPI `PCI0.GPP4` `AE_ALREADY_EXISTS`

**Prioridad:** P4 (exploratorio)  
**Relacionado con:** posible dominio PM PCIe cerca de ACP — **sin prueba**

---

## Síntoma (cada cold boot)

```text
ACPI BIOS Error (bug): Failure creating named object [\_SB.PCI0.GPP4._S0W], AE_ALREADY_EXISTS
ACPI BIOS Error (bug): Failure creating named object [\_SB.PCI0.GPP4._PR0], AE_ALREADY_EXISTS
ACPI BIOS Error (bug): Failure creating named object [\_SB.PCI0.GPP4._PR3], AE_ALREADY_EXISTS
```

---

## Contexto

- GPP4: puerto PCIe en tabla ACPI ASUS.
- ACP audio en `0000:c4:00.5` puede compartir jerarquía de power con otros dispositivos `c4:00.x`.
- Dump existente: [`../acpi_debug/`](../acpi_debug/)

---

## Investigación pendiente

- [ ] Localizar GPP4 en `dsdt.dsl` / SSDT y mapear a `c4:00.*`
- [ ] Correlacionar boots con `AE_ALREADY_EXISTS` vs Track A `-110` (tabla cruzada)
- [ ] Comparar con firmware Windows / BIOS version
- [ ] Kernel quirk vs fix BIOS (fuera de alcance snd_repair salvo evidencia)

---

## Criterio de cierre

- Documentar “benigno” **o**
- Abrir bug ASUS/ACPI con evidencia si correlación >80% con fallos resume

---

## Referencias

- [`../acpi_debug/acpi_tables.txt`](../acpi_debug/acpi_tables.txt)
- [`../FAILURE-REPORT-2026-07-09.md`](../FAILURE-REPORT-2026-07-09.md) § L7
