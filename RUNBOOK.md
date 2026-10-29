# Runbook - L2 Troubleshooting & Disaster Recovery

Questo documento contiene le procedure operative standard (SOP) per la diagnosi e la risoluzione di incidenti di Livello 2 sull'infrastruttura della Voting App.
Gli scenari descritti sono riproducibili localmente tramite i target del Makefile.

---

## Scenario 1: Fallimento Rilascio Applicativo (Guasto all'Immagine)

### 1. Sintomo
Durante un ciclo di aggiornamento, i nuovi pod del componente `worker` non riescono ad avviarsi. Il servizio complessivo non è in down totale, ma i nuovi voti potrebbero non essere processati tempestivamente.

**Trigger per la simulazione:**
```bash
make incident-image
```

### 2. Comandi di Diagnosi ed Evidenze
Si indaga lo stato dei pod nel namespace per individuare anomalie:
```bash
kubectl --context kind-voting-cluster get pods -n voting-app
```
**Evidenza riscontrata:**
```text
NAME                      READY   STATUS             RESTARTS   AGE
db-66b94fc5f7-nww8d       1/1     Running            0          2m46s
redis-796dc594bb-hkjpg    1/1     Running            0          2m46s
result-565df48cf9-pwnq4   1/1     Running            0          2m46s
vote-7db99fc555-rc5qz     1/1     Running            0          2m46s
worker-5dd767667f-79sxp   1/1     Running            0          2m46s
worker-5ddd7999c4-dpmc5   0/1     ImagePullBackOff   0          80s
```
*Nota: Il pod originale (`worker-5dd767667f-79sxp`) rimane in stato operativo (Running), mentre il nuovo ReplicaSet (`worker-5ddd7999c4-dpmc5`) fallisce il pull.*

### 3. Ipotesi e Causa Confermata
- **Ipotesi:** Il nodo non riesce a scaricare l'immagine dal registry a causa di credenziali mancanti o di un tag inesistente.
- **Causa Confermata:** Un errore ha iniettato un tag immagine non valido (`broken-tag-123`). Grazie al meccanismo di *Rolling Update* del Deployment, Kubernetes ha mantenuto attivo il vecchio ReplicaSet (`Running`), garantendo la continuità del servizio mentre il nuovo pod rimane bloccato in fase di scheduling e fetch dell'immagine (`ImagePullBackOff` / `ErrImagePull`), senza mai avviare il container.

### 4. Correzione (Disaster Recovery)
L'incidente si risolve applicando i principi GitOps per ripristinare lo stato sano:
```bash
make recover-image
make wait-ready
```

### 5. Escalation Policy e Raccolta Evidenze
- **Quando scalare a L3:** Se dopo il rollback il pod continua a dare `ErrImagePull`, il problema non è nel manifest ma a livello di infrastruttura (es. container registry irraggiungibile o limitazioni di rete del nodo).
- **Evidenze da allegare al ticket:** L'output di `kubectl describe pod -l app=worker -n voting-app` mostrerà il fallimento del runtime del container evidenziando l'evento `Failed to pull image`:
```text
Events:
  Type     Reason     Age                   From               Message
  ----     ------     ----                  ----               -------
  Normal   Pulling    2m14s (x4 over 3m)    kubelet            Pulling image "dockersamples/examplevotingapp_worker:broken-tag-123"
  Warning  Failed     2m12s (x4 over 3m)    kubelet            Failed to pull image "dockersamples/examplevotingapp_worker:broken-tag-123": rpc error: code = NotFound desc = failed to pull and unpack image
  Warning  Failed     2m12s (x4 over 3m)    kubelet            Error: ErrImagePull
```

---

## Scenario 2: Irraggiungibilità del Servizio (Buco Nero di Rete)

### 1. Sintomo
Gli utenti non riescono a visualizzare la dashboard dei risultati (errore 502/503 visitando la porta 30001). I pod applicativi risultano in esecuzione.

**Trigger per la simulazione:**
```bash
make incident-service
```

### 2. Comandi di Diagnosi ed Evidenze
Si analizza il networking interno controllando il routing del Service verso gli Endpoint:
```bash
kubectl --context kind-voting-cluster get endpoints result -n voting-app
```
**Evidenza riscontrata:**
```text
NAME     ENDPOINTS   AGE
result   <none>      5m11s
```

### 3. Ipotesi e Causa Confermata
- **Ipotesi:** Il Service non riesce a instradare il traffico ai pod sottostanti per un errore di etichettatura (labels mismatch).
- **Causa Confermata:** Il `selector` del Service `result` è stato alterato (da `app=result` ad `app=app-sbagliata`), svuotando dinamicamente la lista degli indirizzi IP validi associati all'Endpoint. Il traffico entra nel cluster ma non trova la destinazione.

### 4. Correzione (Disaster Recovery)
Si ripristina la mappatura corretta riapplicando l'overlay locale sano:
```bash
make recover-service
```

### 5. Escalation Policy e Raccolta Evidenze
- **Quando scalare a L3 / Network Team:** Se il comando `get endpoints` mostra gli IP corretti, ma il servizio resta irraggiungibile dal browser locale, il problema risiede al di fuori di Kubernetes (es. regole di firewall iptables del nodo host o configurazioni errate di port-forwarding in Docker/Kind).
- **Evidenze da allegare al ticket:** L'output di `kubectl describe svc result -n voting-app` mostrerà lo scollamento tra il selector errato e la totale assenza di Endpoints:
```text
Name:                     result
Namespace:                voting-app
Labels:                   app=result
Annotations:              <none>
Selector:                 app=app-sbagliata
Type:                     NodePort
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.96.3.106
IPs:                      10.96.3.106
Port:                     80  80/TCP
TargetPort:               80/TCP
NodePort:                 80  30001/TCP
Endpoints:                
Session Affinity:         None
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster
Events:                   <none>