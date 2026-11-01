# Utilizzo dell'AI

Ho usato un assistente AI (LLM) come supporto per capire gli strumenti, per le ipotesi di troubleshooting e per bozze di automazione e documentazione. Le scelte tecniche e la responsabilità di ciò che è consegnato sono mie: ogni modifica è stata verificata sul mio cluster.

## Regole che mi sono dato

- Nessun secret o dato sensibile nei prompt.
- Nessun comando eseguito senza averlo capito.
- Distinguere ciò che l'AI ha suggerito da ciò che ho verificato io (ogni caso sotto riporta entrambe le cose).
- Riportare anche i suggerimenti che si sono rivelati sbagliati o incompleti.

## Caso 1 - Sostituire le variabili del database con un riferimento al Secret (troubleshooting)

- **Problema:** volevo togliere `POSTGRES_USER` e `POSTGRES_PASSWORD` in chiaro dal Deployment `db` e usare un Secret. La patch YAML con `$patch: replace` sulla lista `env` non produceva l'effetto voluto: nel render di `kustomize build k8s/overlays/local` il Deployment conservava ancora i valori in chiaro.
- **Supporto AI:** ho chiesto di spiegare il comportamento. L'AI ha indicato che lo strategic merge patch di Kustomize tratta in modo particolare le liste di oggetti e ha suggerito una **JSON Patch inline** (`op: replace` su `/spec/template/spec/containers/0/env`) nel `kustomization.yaml`.
- **Verifica:** ho riscritto la patch e ho controllato il risultato con `kustomize build` (le variabili ora usano `secretKeyRef`) e poi con un deploy sul cluster.
- **Limite del suggerimento:** l'AI proponeva anche di generare una password nuova. Non l'ho fatto: le immagini upstream di `worker` e `result` hanno la password `postgres` scritta nel codice e non si sarebbero più connesse al database. L'AI non conosceva il comportamento di queste immagini.

## Caso 2 - Target `make` per incidenti e ripristino

- **Problema:** serviva un modo ripetibile per provocare un guasto e tornare alla normalità.
- **Supporto AI:** ho chiesto una bozza dei target `make` per applicare gli overlay di guasto (`make incident-image`, `make incident-service`) e per il ripristino, preferendo overlay Kustomize a modifiche dei file con `sed`.
- **Verifica:** ho simulato gli incidenti dal vivo sul cluster, osservato i transitori e controllato con `kubectl get pods` e `get endpoints` che il ripristino riportasse lo stato sano.
- **Cosa ho imparato osservando:** con il rolling update il vecchio Pod del `worker` è rimasto attivo durante l'incidente 1, quindi l'effetto reale è un rilascio bloccato, non un'applicazione ferma. Nel runbook riporto ciò che ho osservato.

## Caso 3 - Errore `CreateContainerConfigError` sull'overlay `custom-options`

- **Problema:** Durante la stesura dell'overlay `custom-options`, il nuovo Pod `vote` andava in `CreateContainerConfigError`.
- **Supporto AI:** L'AI ha ipotizzato che il problema fosse l'hash aggiunto da Kustomize al nome del ConfigMap e mi ha suggerito di aggiungere la direttiva `disableNameSuffixHash: true` per aggirarlo.
- **Verifica e Causa Reale:** Controllando lo stato del cluster, ho scoperto che la vera causa era la mancanza della direttiva `namespace: voting-app` nel `kustomization.yaml` dell'overlay (il ConfigMap veniva generato nel namespace `default` ed era invisibile al Pod). Una volta corretto il namespace, ho testato la configurazione rimuovendo il `disableNameSuffixHash: true` suggerito dall'AI: il deploy ha funzionato. Kustomize risolve i nomi con hash nativamente; l'ipotesi dell'AI era errata.

## Cosa non ho delegato all'AI

- La scelta dell'applicazione e del perimetro.
- L'interpretazione degli output di `kubectl` nei due incidenti e le condizioni di escalation.
- La decisione di mantenere le credenziali `postgres/postgres` per compatibilità tecnica con le immagini upstream.

## Limiti dell'uso dell'AI

- L'AI non conosceva preventivamente il comportamento "hardcoded" delle immagini upstream (es. credenziali di database forzate nel codice compilato).
- Formula costantemente spiegazioni plausibili (come l'errore del ConfigMap) che vanno **sempre e rigorosamente** verificate con prove empiriche sul terminale prima di poterne certificare la validità.