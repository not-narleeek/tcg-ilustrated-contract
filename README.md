# TCG Ilustrated — Smart Contract

Implementación en Solidity del núcleo de la propuesta **TCG Ilustrated**:
autenticación **no destructiva** de productos sellados (cartas / sobres TCG)
mediante un **registro inmutable en blockchain**, sobre la red **Avalanche Fuji
(testnet)**.

## ¿Qué hace el contrato?

`TCGIlustrated.sol` mantiene el estado de cada unidad sellada, anclada por el
**hash de su UID** (`keccak256(UID)` — nunca se guarda el código en claro), y
ejecuta tres operaciones auditables que reflejan el caso real de **falsificación
y re-sellado** en el mercado TCG:

1. **Registro** (`registrar`) — el emisor da de alta el hash del UID y del lote.
   Estado → `REGISTERED`. Emite `SobreRegistrado`.
2. **Verificación** (`verificar` / `detalle` / `esAutentica`) — lectura pública
   y gratuita del estado. Cualquiera puede auditar sin intermediario.
3. **Apertura** (`abrir`) — al reclamar el producto, el estado pasa de forma
   **irreversible** a `OPENED`. Emite `SobreAbierto`.
4. **Anti-fraude** — si se intenta re-registrar un UID existente, **no se
   sobrescribe** el registro legítimo: se deja constancia on-chain del intento
   con el evento `FalsificacionDetectada`.

**Límite honesto:** la blockchain asegura la integridad del *registro*, no impide
clonar la etiqueta física (QR/NFC). En el proyecto completo se combina con
material físico anti-manipulación. La tokenización/NFT es una extensión opcional.

## Cumplimiento de los requisitos

| Requisito | Dónde |
|---|---|
| Variables de estado (mapping/struct/enum/arrays) | `enum Estado`, `struct Sobre`, `mapping(bytes32 => Sobre) sobres`, contadores |
| ≥ 2 funciones con lógica propia | `registrar()`, `abrir()` |
| Modificadores (`require` / `modifier`) | `modifier soloEmisor` + varios `require` |
| ≥ 1 evento | `SobreRegistrado`, `SobreAbierto`, `FalsificacionDetectada` |
| Compila/despliega en Remix + Fuji | `pragma ^0.8.20`, sin dependencias externas |

## Despliegue en Remix IDE sobre Avalanche Fuji

1. Abrir <https://remix.ethereum.org> y crear `TCGIlustrated.sol` con el contenido
   del archivo.
2. **Solidity Compiler** → versión `0.8.20` (o superior 0.8.x) → *Compile*.
3. En MetaMask, agregar la red **Avalanche Fuji C-Chain**:
   - Network name: `Avalanche Fuji C-Chain`
   - RPC URL: `https://api.avax-test.network/ext/bc/C/rpc`
   - Chain ID: `43113`
   - Símbolo: `AVAX`
   - Explorer: `https://testnet.snowtrace.io`
4. Obtener AVAX de prueba en el faucet: <https://faucet.avax.network> (o
   <https://core.app/tools/testnet-faucet/>).
5. En Remix → **Deploy & Run** → Environment: *Injected Provider - MetaMask*
   → *Deploy*. Confirmar la transacción.

## Cómo probar

Para los parámetros `bytes32`, usar el helper de Remix o `keccak256` de un texto.
En Remix puedes pasar directamente, por ejemplo, el resultado de aplicar keccak a
`"UID-001"`. (Atajo: en la consola de Remix
`web3.utils.keccak256("UID-001")`.)

1. `registrar(keccak256("UID-001"), keccak256("LOTE-A"))` desde el emisor →
   evento `SobreRegistrado`; `verificar` devuelve `1 (REGISTERED)`.
2. `registrar` del mismo UID otra vez → evento `FalsificacionDetectada`, el
   registro original no cambia; `totalIntentosFalsificacion` aumenta.
3. `abrir(keccak256("UID-001"))` → evento `SobreAbierto`; `verificar` devuelve
   `2 (OPENED)`.
4. `abrir` de nuevo → revierte (irreversibilidad).
5. `registrar` desde otra cuenta → revierte por `soloEmisor`.

## Archivos

- `TCGIlustrated.sol` — contrato + explicación en cabecera (entregables 4 y 5).
- `README.md` — este documento.
