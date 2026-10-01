# cpu-policy — Политика P+E ядер

`Get-PerformanceCoreMask.ps1` — динамическое определение маски P-ядер (хардкод запрещён, AR-704); `Set-WorkloadAffinity.ps1` — привязка сборок и `vmmemWSL` к P-ядрам (AR-705); `power-plan.json` — параметры схемы питания. Метод определения — ADR-0010 (динамика на каждой загрузке).
