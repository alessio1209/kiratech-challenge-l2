# Integrazione con Krateo PlatformOps (Concettuale)

Questo documento illustra l'approccio teorico per trasformare l'attuale infrastruttura GitOps in un template *Self-Service* utilizzabile tramite **Krateo PlatformOps**. 
*Nota: L'implementazione pratica non è stata eseguita, l'analisi è puramente concettuale.*

## 1. Cosa diventerebbe Template
L'intera directory `k8s/base` e i concetti applicati nell'overlay `local` verrebbero pacchettizzati in un modulo (tramite Crossplane Composition / Krateo Provider). Krateo esporrebbe un'interfaccia grafica per richiedere l'ambiente.

## 2. Parametri (Input) richiesti all'utente
Il form Self-Service su Krateo chiederebbe allo sviluppatore solo parametri di alto livello:
- **Nome Applicazione:** (es. `voting-app-demo`)
- **Namespace di destinazione:** (es. `team-frontend-dev`)
- **Ambiente:** Dropdown (`Sviluppo`, `Staging`, `Produzione`). *Selezionando "Sviluppo" si applicherebbero i limiti di risorse rigorosi; selezionando "Produzione" si scalerebbero le repliche.*
- **Tag Immagine Worker:** (es. `latest` o un hash specifico)

## 3. Benefici dell'approccio Krateo
- **Democratizzazione (Self-Service):** Gli sviluppatori accendono ambienti in autonomia senza conoscere Kustomize o le JSON Patch.
- **Sicurezza By-Design:** Krateo gestirebbe l'integrazione con un Vault esterno in modo invisibile, evitando il transito di file `.env`.
- **Standardizzazione:** Imposizione di policy aziendali centralizzate (es. obbligo di Liveness/Readiness probes).

