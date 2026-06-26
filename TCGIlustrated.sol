// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TCGIlustrated
 * @author Proyecto Blockchain - TCG Ilustrated (M. Vasquez, A. Saldias)
 * @notice Registro inmutable para autenticacion NO destructiva de productos
 *         sellados en el mercado de Trading Card Games (TCG / sobres Pokemon).
 *
 * ====================================================================
 *  QUE HACE ESTE CONTRATO
 * ====================================================================
 *  El caso real: falsificacion y re-sellado de producto sellado en el
 *  mercado TCG (USD 218.000 en cartas falsas incautadas por CBP en 2012;
 *  booster boxes re-sellados detectados al abrirse). Hoy NO existe un
 *  metodo estandar, universal y verificable para validar la autenticidad
 *  e integridad del sello sin destruir el empaque; los metodos vigentes
 *  (pesaje, contraluz, inspeccion del sellado) son heuristicos y no
 *  concluyentes.
 *
 *  Este contrato implementa el nucleo de la propuesta: un registro
 *  on-chain donde cada unidad sellada queda anclada por el HASH de su
 *  identificador unico (UID). Se eligio blockchain en lugar de una base
 *  de datos centralizada por su INMUTABILIDAD (el estado no se puede
 *  reescribir), TRANSPARENCIA (cualquiera verifica) y porque el contrato
 *  actua como verificador neutral, sin intermediario de confianza.
 *
 *  Flujo (slides 5-6 de la presentacion):
 *    1. REGISTRO     - el emisor da de alta el hash del UID -> REGISTERED.
 *    2. VERIFICACION - el comprador consulta el estado (lectura gratuita).
 *    3. APERTURA     - al reclamar/abrir se fija OPENED de forma irreversible.
 *    4. ANTI-FRAUDE  - un UID duplicado no puede re-registrarse: se marca
 *                      on-chain como intento de falsificacion.
 *
 *  Privacidad: se guarda keccak256(UID), nunca el codigo en claro.
 *
 *  LIMITE HONESTO (slide 4 y 7): la blockchain asegura la integridad del
 *  REGISTRO, no impide clonar la etiqueta fisica (QR/NFC). Por eso, en el
 *  proyecto completo, este registro se combina con material fisico
 *  anti-manipulacion. La capa de tokenizacion/NFT es una extension
 *  opcional, no una condicion del concepto.
 *
 * ====================================================================
 *  RELACION CON LOS REQUISITOS DE LA TAREA
 * ====================================================================
 *   - Variables de estado: enum Estado, struct Sobre, mapping sobres,
 *     contadores totalRegistrados / totalAperturas.
 *   - >=2 funciones con logica propia: registrar() y abrir().
 *   - Modificadores: modifier soloEmisor + multiples require.
 *   - Eventos: SobreRegistrado, SobreAbierto, FalsificacionDetectada.
 *   - Compila y se despliega en Remix sobre Avalanche Fuji (chainId 43113).
 */
contract TCGIlustrated {
    // ----------------------------------------------------------------
    //  Tipos
    // ----------------------------------------------------------------

    /// @notice Ciclo de vida de una unidad sellada.
    enum Estado {
        NO_REG,     // 0 - nunca registrado
        REGISTERED, // 1 - dado de alta por el emisor, sin abrir
        OPENED,     // 2 - abierto/reclamado (irreversible)
        FAKE        // 3 - reservado para marcar unidades comprometidas
    }

    /// @notice Datos auditables de cada unidad. No se almacena el UID en claro.
    struct Sobre {
        Estado estado;     // estado actual
        bytes32 hashLote;  // hash del lote de produccion
        address emisor;    // quien registro la unidad
        uint256 fecha;     // marca de tiempo del registro (block.timestamp)
    }

    // ----------------------------------------------------------------
    //  Estado del contrato
    // ----------------------------------------------------------------

    /// @notice clave = keccak256(UID) => datos del sobre.
    mapping(bytes32 => Sobre) public sobres;

    /// @notice Cuenta autorizada a registrar (fijada en el despliegue).
    address public emisor;

    /// @notice Metricas publicas de auditoria.
    uint256 public totalRegistrados;
    uint256 public totalAperturas;
    uint256 public totalIntentosFalsificacion;

    // ----------------------------------------------------------------
    //  Eventos
    // ----------------------------------------------------------------

    event SobreRegistrado(
        bytes32 indexed uid,
        bytes32 hashLote,
        address indexed emisor,
        uint256 fecha
    );

    event SobreAbierto(bytes32 indexed uid, address indexed abiertoPor, uint256 fecha);

    event FalsificacionDetectada(bytes32 indexed uid, address indexed quien, uint256 fecha);

    // ----------------------------------------------------------------
    //  Modificadores
    // ----------------------------------------------------------------

    /// @notice Restringe la accion a la cuenta emisora.
    modifier soloEmisor() {
        require(msg.sender == emisor, "TCG: solo el emisor");
        _;
    }

    // ----------------------------------------------------------------
    //  Constructor
    // ----------------------------------------------------------------

    /// @notice El emisor es quien despliega el contrato.
    constructor() {
        emisor = msg.sender;
    }

    // ----------------------------------------------------------------
    //  Logica principal
    // ----------------------------------------------------------------

    /**
     * @notice Da de alta una unidad sellada (paso 1: REGISTRO).
     * @dev Anti-fraude: si el UID ya existe NO se sobrescribe el registro
     *      legitimo; se deja constancia on-chain del intento de
     *      falsificacion y la transaccion termina sin alterar el estado.
     * @param uid  keccak256 del identificador unico de la unidad.
     * @param lote keccak256 del lote de produccion.
     */
    function registrar(bytes32 uid, bytes32 lote) external soloEmisor {
        require(uid != bytes32(0), "TCG: uid invalido");

        // Anti-fraude (paso 4): un UID duplicado no puede re-registrarse.
        if (sobres[uid].estado != Estado.NO_REG) {
            totalIntentosFalsificacion += 1;
            emit FalsificacionDetectada(uid, msg.sender, block.timestamp);
            return;
        }

        sobres[uid] = Sobre({
            estado: Estado.REGISTERED,
            hashLote: lote,
            emisor: msg.sender,
            fecha: block.timestamp
        });

        totalRegistrados += 1;
        emit SobreRegistrado(uid, lote, msg.sender, block.timestamp);
    }

    /**
     * @notice Marca una unidad como abierta (paso 3: APERTURA).
     * @dev Transicion irreversible REGISTERED -> OPENED. Cualquiera con el
     *      UID puede abrir (es el comprador al reclamar el producto).
     * @param uid keccak256 del identificador unico de la unidad.
     */
    function abrir(bytes32 uid) external {
        Sobre storage s = sobres[uid];
        require(s.estado != Estado.NO_REG, "TCG: no registrado");
        require(s.estado == Estado.REGISTERED, "TCG: ya abierto o invalido");

        s.estado = Estado.OPENED;
        totalAperturas += 1;
        emit SobreAbierto(uid, msg.sender, block.timestamp);
    }

    // ----------------------------------------------------------------
    //  Lectura (paso 2: VERIFICACION) - publica y gratuita
    // ----------------------------------------------------------------

    /// @notice Devuelve el estado actual de una unidad.
    function verificar(bytes32 uid) external view returns (Estado) {
        return sobres[uid].estado;
    }

    /// @notice Devuelve el detalle completo de una unidad.
    function detalle(bytes32 uid)
        external
        view
        returns (Estado estado, bytes32 hashLote, address emisorUnidad, uint256 fecha)
    {
        Sobre storage s = sobres[uid];
        return (s.estado, s.hashLote, s.emisor, s.fecha);
    }

    /// @notice true si la unidad esta registrada y aun no fue abierta.
    function esAutentica(bytes32 uid) external view returns (bool) {
        return sobres[uid].estado == Estado.REGISTERED;
    }
}
