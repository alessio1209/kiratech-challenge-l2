# Kiratech L2 Challenge - GitOps Voting App

Questo repository contiene l'infrastruttura as-code per il deploy locale della **Docker Example Voting App**, strutturata secondo i principi GitOps utilizzando Kubernetes (Kind), Kustomize e un Makefile per l'orchestrazione.

L'applicazione upstream originale è reperibile qui: [Docker Example Voting App](https://github.com/dockersamples/example-voting-app).

### 🎯 Scelta dell'Applicativo (Voting App vs Online Boutique)

Sebbene la challenge suggerisse come possibile opzione la *Google Online Boutique*, è stata scelta la *Docker Voting App* per un'attenta **ottimizzazione delle risorse computazionali**. L'Online Boutique è notoriamente esosa in termini di RAM e CPU, e su un cluster locale come Kind può facilmente portare a instabilità, rallentamenti o errori di `OOMKilled` sulle macchine di sviluppo standard.
La *Voting App*, al contrario, rappresenta il perfetto compromesso: permette di dimostrare un'architettura a microservizi multi-livello eterogenea (linguaggi diversi, code asincrone, cache in memoria e database relazionali) mantenendo un footprint estremamente leggero, garantendo al valutatore un'esperienza di test fluida, rapida e totalmente riproducibile.

## 🏗️ Architettura dell'Infrastruttura

Di seguito il diagramma architetturale dei flussi di rete e delle dipendenze tra i microservizi, esposti localmente tramite NodePort:

```
graph TD
    Client([Browser Locale]) -->|Porta 30000| Vote[Vote App - Python]
    Client -->|Porta 30001| Result[Result App - Node.js]
    
    Vote -->|TCP 6379| Redis[(Redis - Cache)]
    Worker[Worker - .NET] -->|TCP 6379| Redis
    Worker -->|TCP 5432| DB[(PostgreSQL - Database)]
    Result -->|TCP 5432| DB

```

## 🛠️ Prerequisiti

Per eseguire correttamente il cluster sul proprio ambiente locale, è necessario avere installati:

* **Docker** (Motore per l'avvio dei nodi virtuali)

* **Kind** (Kubernetes IN Docker)

* **Kubectl** (CLI per interagire con il cluster)

* **Make** (Per l'esecuzione dei target di automazione)

## 🚀 Guida all'Avvio Rapido (Quickstart)

**1. Verifica dei prerequisiti**

```
make doctor

```

**2. Generazione delle Credenziali Locali**
Per rispettare le best practice di sicurezza, il file `.env` contenente le credenziali per la generazione dinamica dei Secret è escluso dal versionamento (`.gitignore`). Prima di procedere, generare il file locale partendo dal template fornito:

```
cp k8s/overlays/local/.env.example k8s/overlays/local/.env

```

**3. Creazione del Cluster**
Viene eseguito il provisioning di un cluster Kind nominato `voting-cluster` con mappatura `extraPortMappings` verso l'host locale:

```
make cluster-up

```

**4. Rilascio dell'Infrastruttura (Deploy)**
Applica i manifest tramite Kustomize, processando l'overlay locale per l'iniezione sicura dei Secret, l'imposizione di resource limits e health probes:

```
make deploy

```

**5. Verifica dello Stato**
Attende in modo dichiarativo che tutti i Pod entrino in stato `Ready`:

```
make wait-ready

```

**6. Validazione Applicativa (Smoke Test)**
Esegue chiamate HTTP reali verso i servizi NodePort per validare il routing end-to-end:

```
make smoke-test

```

## 🌐 Accesso all'Applicazione

L'architettura espone i servizi esternamente tramite NodePort:

* **Interfaccia di Voto (Vote):** <http://localhost:30000>

* **Dashboard Risultati (Result):** <http://localhost:30001>

## 🔄 Dimostrazione Riconfigurazione (Punto 7)

Il repository include target specifici per dimostrare la riconfigurazione dell'applicativo, evidenziando la differenza tra approccio dichiarativo e imperativo:

* **Approccio Dichiarativo (GitOps):** Tramite `make change-voting-options` viene applicato un overlay Kustomize che inietta un ConfigMap nel frontend, cambiando dinamicamente le opzioni di voto (da Cats/Dogs a Pizza/Pasta) tramite Rolling Update, a zero disservizio.

* **Approccio Imperativo (Emergenza):** Tramite `make scale-up` viene dimostrato lo scale-out orizzontale rapido (da 1 a 3 repliche) del frontend per assorbire un picco di traffico improvviso.

## 🧹 Pulizia dell'Ambiente (Tear Down)

```
make cluster-down

```

## 🔍 Troubleshooting e Ostacoli Superati (Lessons Learned)

Durante lo sviluppo e l'ingegnerizzazione dell'overlay, sono state affrontate e risolte le seguenti sfide architetturali:

### 1. Limiti dello Strategic Merge Patch sui Secret

* **Problema:** Kustomize faticava a sovrascrivere in modo pulito l'array `env` del container `postgres` tramite un file di patch YAML standard. A causa della logica di default dello *Strategic Merge Patch*, tendeva ad affiancare la password in chiaro originale al nuovo riferimento `valueFrom:`, ignorando la direttiva `$patch: replace`.

* **Soluzione:** È stato eseguito un override deterministico bypassando lo Strategic Merge Patch tramite l'uso di una **JSON Patch inline** (`op: replace`) direttamente all'interno del `kustomization.yaml`.

### 2. Fallimento della pipeline CI (GitHub Actions)

* **Problema:** L'implementazione della best practice per nascondere il file `.env` tramite `.gitignore` ha causato il fallimento del workflow di CI su GitHub, poiché l'ambiente virtuale non trovava il file delle credenziali.

* **Soluzione:** È stata integrata una logica di preparazione nell'automazione del workflow `ci.yml`, replicando il comando `cp k8s/overlays/local/.env.example k8s/overlays/local/.env` prima della validazione.