# Runbook L2 - Voting App su Kubernetes locale

Procedure per la diagnosi e il ripristino di due incidenti riproducibili. Ogni scenario segue lo stesso schema: sintomo, evidenze, ipotesi, causa confermata, correzione, verifica finale, escalation.

Gli esempi usano il contesto `kind-voting-cluster` e il namespace `voting-app` (i target `make` li impostano già).

## Controlli iniziali (sempre, prima di toccare qualcosa)

Ordine consigliato: dal quadro generale al dettaglio.

```bash
# 1. Stato generale: Pod e Service con i loro endpoint
kubectl --context kind-voting-cluster get pods,svc,endpoints -n voting-app        # make verify

# 2. Eventi recenti, in ordine temporale
kubectl --context kind-voting-cluster get events -n voting-app --sort-by=.metadata.creationTimestamp   # make events

# 3. Dettaglio del Pod sospetto (sezione Events in fondo)
kubectl --context kind-voting-cluster describe pod <nome-pod> -n voting-app

# 4. Log del componente
kubectl --context kind-voting-cluster logs deployment/<nome> -n voting-app --tail=50    # make logs APP=<nome>
# Se il container e' stato riavviato: aggiungere --previous

# 5. Il percorso del voto funziona? (vote -> redis -> worker -> db)
make e2e-test
```

Cosa guardare:

| Segnale | Significato probabile |
|---|---|
| `ImagePullBackOff` / `ErrImagePull` | immagine o tag inesistente, registry non raggiungibile |
| `CrashLoopBackOff` | il container parte e termina: leggere `logs --previous` |
| `Running` ma `0/1 READY` | readiness probe fallita |
| Service con `ENDPOINTS <none>` | il selector non corrisponde a nessun Pod pronto |
| Pod `Pending` | risorse insufficienti o problema di scheduling: vedere gli eventi |

---

## Scenario 1: Fallimento rilascio applicativo (immagine inesistente)

### 1. Sintomo

Dopo un aggiornamento, i nuovi Pod del `worker` non si avviano. L'applicazione resta raggiungibile, ma un `worker` aggiornato non sta entrando in servizio.

Simulazione:

```bash
make incident-image
```

Modifica introdotta: l'overlay `k8s/overlays/incident-image` cambia il tag dell'immagine del `worker` in `broken-tag-123`, che non esiste.

### 2. Comandi ed evidenze

```bash
kubectl --context kind-voting-cluster get pods -n voting-app
```

Evidenza:

```text
NAME                      READY   STATUS             RESTARTS   AGE
db-66b94fc5f7-whzjw       1/1     Running            0          3h30m
redis-796dc594bb-v74wk    1/1     Running            0          3h30m
result-565df48cf9-5m7gf   1/1     Running            0          3h30m
vote-7db99fc555-btnwf     1/1     Running            0          179m
worker-5dd767667f-x75jz   1/1     Running            0          3h30m
worker-5ddd7999c4-2d6pg   0/1     ImagePullBackOff   0          17s
```

Il Pod originale (`worker-5dd767667f-x75jz`) resta `Running`, mentre quello del nuovo ReplicaSet (`worker-5ddd7999c4-2d6pg`) non parte.

```bash
make events
```

Evidenza:

```text
LAST SEEN   TYPE      REASON              OBJECT                          MESSAGE
116s        Normal    Scheduled           pod/worker-5ddd7999c4-2d6pg     Successfully assigned voting-app/worker-5ddd7999c4-2d6pg to voting-cluster-control-plane
116s        Normal    SuccessfulCreate    replicaset/worker-5ddd7999c4    Created pod: worker-5ddd7999c4-2d6pg
116s        Normal    ScalingReplicaSet   deployment/worker               Scaled up replica set worker-5ddd7999c4 to 1 from 0
31s         Normal    Pulling             pod/worker-5ddd7999c4-2d6pg     Pulling image "dockersamples/examplevotingapp_worker:broken-tag-123"
30s         Warning   Failed              pod/worker-5ddd7999c4-2d6pg     Failed to pull image "dockersamples/examplevotingapp_worker:broken-tag-123": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/dockersamples/examplevotingapp_worker:broken-tag-123": failed to resolve reference "docker.io/dockersamples/examplevotingapp_worker:broken-tag-123": docker.io/dockersamples/examplevotingapp_worker:broken-tag-123: not found
30s         Warning   Failed              pod/worker-5ddd7999c4-2d6pg     Error: ErrImagePull
6s          Normal    BackOff             pod/worker-5ddd7999c4-2d6pg     Back-off pulling image "dockersamples/examplevotingapp_worker:broken-tag-123"
19s         Warning   Failed              pod/worker-5ddd7999c4-2d6pg     Error: ImagePullBackOff
```

Evidenza (output del Rollout):
```bash
kubectl --context kind-voting-cluster rollout status deployment/worker -n voting-app --timeout=30s
```
```text
Waiting for deployment "worker" rollout to finish: 1 old replicas are pending termination...
error: timed out waiting for the condition
```

### 3. Ipotesi e causa confermata

- **Ipotesi:** il nodo non riesce a scaricare l'immagine, per tag inesistente, registry non raggiungibile o credenziali mancanti.
- **Verifica:** il messaggio `NotFound ... failed to pull and unpack image` indica che il tag richiesto non esiste. Gli altri Pod (che scaricano immagini dallo stesso registry) non hanno problemi, quindi il registry è raggiungibile.
- **Causa confermata:** l'immagine del `worker` punta al tag inesistente `broken-tag-123`. Il Pod è stato schedulato correttamente sul nodo, ma il pull dell'immagine fallisce e il container non viene mai avviato.

**Impatto osservato:** grazie al rolling update, Kubernetes mantiene attivo il Pod del vecchio ReplicaSet finché quello nuovo non è pronto. Il servizio non va giù, ma il rilascio resta bloccato e la nuova versione non entra in servizio.

### 4. Correzione

```bash
make recover-image
make wait-ready
```

`recover-image` riapplica l'overlay `local`, che riporta il Deployment al riferimento corretto. In alternativa, per tornare alla revisione precedente senza passare da Kustomize:

```bash
kubectl --context kind-voting-cluster rollout undo deployment/worker -n voting-app
```

Dopo un `rollout undo`, il cluster non coincide più con il repository: è un rimedio rapido per l'emergenza, da riallineare poi al manifest in Git.

### 5. Verifica finale

```bash
make verify          # tutti i Pod Running, worker 1/1 senza Pod in ImagePullBackOff
make e2e-test        # il voto arriva nel database
```

Esito della verifica reale post-incident:
```text
NAME                          READY   STATUS    RESTARTS   AGE
pod/db-66b94fc5f7-whzjw       1/1     Running   0          3h35m
pod/redis-796dc594bb-v74wk    1/1     Running   0          3h35m
pod/result-565df48cf9-5m7gf   1/1     Running   0          3h35m
pod/vote-7db99fc555-btnwf     1/1     Running   0          3h4m
pod/worker-5dd767667f-x75jz   1/1     Running   0          3h35m

NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/db       ClusterIP   10.96.225.219   <none>        5432/TCP       3h35m
service/redis    ClusterIP   10.96.225.224   <none>        6379/TCP       3h35m
service/result   NodePort    10.96.120.212   <none>        80:30001/TCP   3h35m
service/vote     NodePort    10.96.155.147   <none>        80:30000/TCP   3h35m

NAME               ENDPOINTS         AGE
endpoints/db       10.244.0.5:5432   3h35m
endpoints/redis    10.244.0.6:6379   3h35m
endpoints/result   10.244.0.7:80     3h35m
endpoints/vote     10.244.0.17:80    3h35m
```
```text
Voti nel database prima del test: 2
Voto inviato a http://localhost:30000
OK: il voto e' arrivato nel database (2 -> 3)
```

### 6. Escalation

Passare a L3 / team piattaforma se:

- dopo il recovery il Pod continua a dare `ErrImagePull` con un tag valido: il problema non è nel manifest ma nell'accesso al registry o nella rete del nodo;
- il tag corretto non risulta pubblicato dal team applicativo;
- il rollout non si completa entro un tempo concordato (ad esempio 10 minuti) nonostante il rollback.

Informazioni da allegare al ticket:
- output di `kubectl get pods -n voting-app` e `make events` (con gli eventi `Failed to pull image`);
- immagine e tag richiesti, e ultimo tag funzionante;
- ora di inizio dell'anomalia e ultimo deploy eseguito;
- cosa è già stato provato (recover, rollout undo) e con quale esito.

---

## Scenario 2: Service non raggiungibile (selector errato)

### 1. Sintomo

La pagina dei risultati (`http://localhost:30001`) non si carica e restituisce un errore di connessione TCP (es. `ERR_CONNECTION_REFUSED` sul browser). Tutti i Pod risultano `Running`, quindi il problema non è nel workload.

Simulazione:

```bash
make incident-service
```

Modifica introdotta: l'overlay `k8s/overlays/incident-service` cambia il selector del Service `result` da `app=result` ad `app=app-sbagliata`.

### 2. Comandi ed evidenze

```bash
kubectl --context kind-voting-cluster get pods -n voting-app                   # i Pod sono Running
kubectl --context kind-voting-cluster get endpoints result -n voting-app       # il Service ha endpoint?
kubectl --context kind-voting-cluster get svc result -n voting-app -o jsonpath='{.spec.selector}{"\n"}'
kubectl --context kind-voting-cluster get pods -n voting-app --show-labels     # label reali dei Pod
```

Evidenza (`get endpoints` e `get svc -o jsonpath`):

```text
NAME     ENDPOINTS   AGE
result   <none>      9m44s

{"app":"app-sbagliata"}
```

Evidenza (etichette dei pod):
```text
NAME                          READY   STATUS    RESTARTS   AGE   LABELS
db-66b94fc5f7-whzjw           1/1     Running   0          10m   app=db,pod-template-hash=66b94fc5f7
redis-796dc594bb-v74wk        1/1     Running   0          10m   app=redis,pod-template-hash=796dc594bb
result-565df48cf9-5m7gf       1/1     Running   0          10m   app=result,pod-template-hash=565df48cf9
vote-7db99fc555-w8b59         1/1     Running   0          10m   app=vote,pod-template-hash=7db99fc555
worker-5dd767667f-x75jz       1/1     Running   0          10m   app=worker,pod-template-hash=5dd767667f
```

Nota: nelle versioni recenti di kubectl `get endpoints` può mostrare un avviso di deprecazione; in alternativa si possono consultare gli EndpointSlice con `kubectl get endpointslices -n voting-app`.

### 3. Ipotesi e causa confermata

- **Ipotesi:** il Service non seleziona i Pod per una differenza tra il suo `selector` e le label dei Pod.
- **Verifica:** il selector del Service è `app=app-sbagliata`, il Pod `result` ha `app=result`; nessun Pod corrisponde, quindi la lista degli endpoint è vuota. I Pod sono sani: il traffico arriva al nodo ma viene droppato a livello TCP.
- **Causa confermata:** selector alterato, da `app=result` ad `app=app-sbagliata`.

### 4. Correzione

```bash
make recover-service
```

Riapplica l'overlay `local`, che ripristina il selector corretto.

### 5. Verifica finale

```bash
kubectl --context kind-voting-cluster get endpoints result -n voting-app    # deve mostrare un IP:80
make smoke-test                                                              # la pagina 30001 risponde
```

Esito della verifica post-incident:
```text
NAME     ENDPOINTS      AGE
result   10.244.0.7:80  20m

Controllo che le interfacce esposte rispondano...
OK Vote App risponde (HTTP < 400)
OK Result App risponde (HTTP < 400)
```

### 6. Escalation

Passare a L3 / team rete o piattaforma se:

- `get endpoints` mostra gli IP corretti ma la pagina resta irraggiungibile dal browser locale: il problema è fuori dal Service (mappatura delle porte di kind in `kind-config.yaml`, rete Docker, firewall dell'host);
- i Pod `result` non risultano `Ready` e gli eventi non spiegano il motivo;
- il problema riguarda più Service contemporaneamente.

Informazioni da allegare al ticket:
- output di `kubectl describe svc result`, `get endpoints result` e `get pods --show-labels`;
- ora di inizio e ultima modifica applicata;
- esito di `make smoke-test` e `make e2e-test`;
- cosa è già stato provato.