# Utilizzo dell'Intelligenza Artificiale (Generative AI)

La Generative AI (LLM) è stata utilizzata come "Pair Programmer" e assistente al troubleshooting, mantenendo il pieno controllo critico sull'architettura e sulle scelte ingegneristiche finali.

Di seguito i casi d'uso reali affrontati durante lo sviluppo:

## Caso 1: Risoluzione del bug di Kustomize sulle liste (Troubleshooting L2)
- **Il Problema:** La patch YAML standard usata per iniettare il `valueFrom` nel container `postgres` falliva. Kustomize non sovrascriveva il `value` in chiaro originale, unendo i due campi e causando un errore API.
- **Supporto AI:** L'AI ha identificato che lo *Strategic Merge Patch* di Kustomize ha limiti noti nella sovrascrittura di array di oggetti (come la lista `env`) e ha suggerito di aggirare il problema iniettando una **JSON Patch inline** (`op: replace`) nel file `kustomization.yaml`.
- **Verifica e Limiti Critici:** Ho testato la soluzione validando il live-state. La tecnica era corretta, tuttavia, l'AI consigliava inizialmente di generare una password completamente nuova. Ho dovuto ignorare il consiglio applicando il giudizio critico: cambiando la password, l'immagine `worker` upstream (che ha la password `postgres` hardcodata) non si sarebbe più connessa. L'AI mancava del contesto applicativo globale.

## Caso 2: Automazione Disaster Recovery (Shell Scripting / Make)
- **Il Problema:** Necessità di creare un sistema ripetibile per scatenare gli incidenti e dimostrare i successivi rollback durante il colloquio.
- **Supporto AI:** Ho chiesto all'AI di abbozzare i target del `Makefile` per l'applicazione degli overlay di fault (es. `make incident-image`).
- **Verifica:** I comandi erano corretti e idempotenti. Li ho verificati simulando l'incidente dal vivo, osservando i transitori e confermando il corretto ripristino dell'endpoint dopo il comando di recover.

## Caso 3: Gestione dell'Hash nei ConfigMap (Troubleshooting App)
- **Il Problema:** Durante la stesura dell'overlay `custom-options` per variare il frontend, il nuovo pod andava in `CreateContainerConfigError`.
- **Supporto AI:** Analizzando i log e l'output di `get cm`, l'AI mi ha guidato a comprendere che Kustomize genera di default un hash casuale come suffisso nel nome del ConfigMap (es. `vote-options-66hbtb5hg7`). La patch applicata al deployment cercava invece il nome esatto.
- **Soluzione:** È stata applicata la direttiva `disableNameSuffixHash: true` nel `kustomization.yaml` per garantire la corretta associazione tra il Deployment patchato e il ConfigMap generato, risolvendo il blocco e completando il Rolling Update.