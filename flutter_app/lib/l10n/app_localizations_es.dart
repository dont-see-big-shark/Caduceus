// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Caduceus';

  @override
  String get settings => 'Configuración';

  @override
  String get settingsItemModel => 'Modelo';

  @override
  String get settingsItemChat => 'Chat';

  @override
  String get settingsItemWorkspace => 'Área de trabajo';

  @override
  String get settingsItemSafety => 'Seguridad';

  @override
  String get settingsItemMemory => 'Memoria y contexto';

  @override
  String get settingsItemAdvanced => 'Avanzado';

  @override
  String get settingsItemNotifications => 'Notificaciones';

  @override
  String get settingsItemBilling => 'Facturación';

  @override
  String get settingsItemProviders => 'Proveedores';

  @override
  String get settingsItemShortcuts => 'Atajos de teclado';

  @override
  String get settingsItemToolsKeys => 'Herramientas y claves';

  @override
  String get settingsItemPlugins => 'Complementos';

  @override
  String get settingsItemArchived => 'Chats archivados';

  @override
  String get settingsItemAbout => 'Acerca de';

  @override
  String get settingsGroupCore => 'Principal';

  @override
  String get settingsGroupDevice => 'Dispositivo';

  @override
  String get settingsGroupAccount => 'Cuenta y conexión';

  @override
  String get settingsGroupSystem => 'Sistema';

  @override
  String get designSurfaceExample => 'Ejemplo · superficie de diseño';

  @override
  String get designSurfaceNoData =>
      'Esta es la página del diseño y la puerta de enlace aún no tiene una superficie detrás. Se muestra como ejemplo etiquetado, sin controles inventados.';

  @override
  String get composerFootCmd => 'Comandos ⌘K';

  @override
  String get composerFootHints => '↵ enviar · ⇧↵ nueva línea · Esc cerrar';

  @override
  String get settingsSubtitle => 'Caduceus y el servidor Hermes';

  @override
  String get appearance => 'Apariencia';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Seguir el sistema';

  @override
  String get languageEn => 'English';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageZhTW => '繁體中文';

  @override
  String get languageJa => '日本語';

  @override
  String get languageEs => 'Español';

  @override
  String get material => 'Material';

  @override
  String get reduceVisualEffects => 'Reducir efectos visuales';

  @override
  String get whatItChanges => 'Qué cambia';

  @override
  String get whatItChangesDesc =>
      'Paneles sólidos en lugar de cristal y sin aurora. Todas las dimensiones, curvas y duraciones se mantienen igual.';

  @override
  String get solid => 'sólido';

  @override
  String get glass => 'cristal';

  @override
  String get session => 'Sesión';

  @override
  String get modelAndSession => 'Modelo y sesión';

  @override
  String get approvals => 'Aprobaciones';

  @override
  String get skills => 'Habilidades';

  @override
  String get voice => 'Voz';

  @override
  String get gateway => 'Pasarela';

  @override
  String get device => 'Dispositivo';

  @override
  String get about => 'Acerca de';

  @override
  String get connection => 'Conexión';

  @override
  String get connected => 'Conectado';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get pickGroupOnLeft => 'Elige un grupo a la izquierda';

  @override
  String get model => 'Modelo';

  @override
  String get thisSession => 'Esta sesión';

  @override
  String get changingIt => 'Cambiarlo';

  @override
  String get changingItDesc =>
      'El selector está en el compositor, al lado del campo al que responderá.';

  @override
  String get workingDirectory => 'Directorio de trabajo…';

  @override
  String get noSessionOpen => 'sin sesión abierta';

  @override
  String get dictation => 'Dictado';

  @override
  String get running => 'Ejecutando';

  @override
  String get idle => 'Inactivo';

  @override
  String get whereItRuns => 'Dónde se ejecuta';

  @override
  String get onThisDevice => 'En este dispositivo';

  @override
  String get address => 'Dirección';

  @override
  String get status => 'Estado';

  @override
  String get version => 'Versión';

  @override
  String get back => 'Atrás';

  @override
  String get connectNewBackend => 'Conectar nuevo backend';

  @override
  String get connectNewBackendSubtitle => 'Descubrir · Vincular · Diagnosticar';

  @override
  String get connectToHermesDesc =>
      'Conectar al plano de control Hermes. Crea un túnel por SSH o Tailscale.';

  @override
  String get addAnotherServer => 'Añadir otro servidor';

  @override
  String get sessionEndedWithError => 'La sesión finalizó con un error';

  @override
  String get nameOptional => 'Nombre (opcional)';

  @override
  String get serverUrl => 'URL del servidor';

  @override
  String get gatewayToken => 'Token de pasarela';

  @override
  String get sessionToken => 'Token de sesión';

  @override
  String get openClawDeviceNote =>
      'OpenClaw admite un dispositivo nuevo solo cuando un operador lo aprueba.';

  @override
  String get connect => 'Conectar';

  @override
  String get forgetThisServer => 'Olvidar este servidor';

  @override
  String get waitingToBeApproved => 'Esperando aprobación';

  @override
  String get openClawApprovalNote =>
      'La pasarela aceptó el token. Aprueba este dispositivo y vuelve a conectar.';

  @override
  String get copyDeviceId => 'Copiar ID de dispositivo';

  @override
  String get newSession => 'Nueva sesión';

  @override
  String get searchSessions => 'Buscar sesiones';

  @override
  String get refresh => 'Actualizar';

  @override
  String get scheduledJobs => 'Tareas programadas';

  @override
  String get projects => 'Proyectos';

  @override
  String get backgroundProcesses => 'Procesos en segundo plano…';

  @override
  String get agents => 'Agentes…';

  @override
  String get checkpoints => 'Puntos de control';

  @override
  String get learningJourney => 'Historial de aprendizaje';

  @override
  String get server => 'Servidor';

  @override
  String get noSessions => 'Sin sesiones';

  @override
  String get noSessionsDesc => 'Inicia una nueva sesión para comenzar';

  @override
  String get reload => 'Recargar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get close => 'Cerrar';

  @override
  String get save => 'Guardar';

  @override
  String get stop => 'Detener';

  @override
  String get stopAll => 'Detener todo';

  @override
  String get delete => 'Eliminar';

  @override
  String get archive => 'Archivar';

  @override
  String get stopThisTitle => '¿Detener esto?';

  @override
  String get stopAllProcessesTitle => '¿Detener todos los procesos?';

  @override
  String get stopAllProcessesMessage =>
      'Se detendrán todos los procesos en segundo plano del servidor.';

  @override
  String get nothingRunning => 'Nada en ejecución';

  @override
  String get hideOutput => 'Ocultar salida';

  @override
  String get showOutput => 'Mostrar salida';

  @override
  String get delegation => 'Delegación';

  @override
  String get noSubagentsRunning => 'Sin subagentes ejecutándose';

  @override
  String get subagentsRunning => 'subagente(s) ejecutándose';

  @override
  String get allowNewSubagents => 'Permitir nuevos subagentes';

  @override
  String get spawningPaused =>
      'Creación pausada — los subagentes en ejecución continúan';

  @override
  String get agentMaySpawnChildren => 'El agente puede crear subagentes';

  @override
  String get savedSpawnTrees => 'Árboles creados guardados';

  @override
  String get noneForThisSession => 'Ninguno para esta sesión';

  @override
  String get recentActivity => 'Actividad reciente';

  @override
  String get interruptThisSubagent => 'Interrumpir este subagente';

  @override
  String get restoreCheckpointTitle => '¿Restaurar punto de control?';

  @override
  String restoreCheckpointMessage(Object hash, Object timestamp) {
    return 'Los archivos del servidor se sobrescribirán al estado de $timestamp ($hash).';
  }

  @override
  String get noCheckpoints => 'Sin puntos de control';

  @override
  String get selectCheckpointToSeeDiff =>
      'Selecciona un punto de control para ver cambios';

  @override
  String get restoreThisCheckpoint => 'Restaurar este punto de control';

  @override
  String restored(Object hash) {
    return 'Restaurado $hash';
  }

  @override
  String get newScheduledJob => 'Nueva tarea programada';

  @override
  String get jobName => 'Nombre';

  @override
  String get schedule => 'Programación';

  @override
  String get scheduleHelper =>
      'expresión cron, ej. 0 9 * * * para las 09:00 diarias';

  @override
  String get promptToRun => 'Instrucción a ejecutar';

  @override
  String get create => 'Crear';

  @override
  String get noScheduledJobs => 'Sin tareas programadas';

  @override
  String get newJob => 'Nueva tarea';

  @override
  String get thisEntryNoLongerAvailable =>
      'Esta entrada ya no está disponible.';

  @override
  String get thisEntryHasNoContentYet => 'Esta entrada aún no tiene contenido.';

  @override
  String get archiveSkillTitle => '¿Archivar habilidad?';

  @override
  String get deleteMemoryTitle => '¿Eliminar memoria?';

  @override
  String archiveSkillContent(Object label) {
    return '\"$label\" se archivará en el servidor.';
  }

  @override
  String deleteMemoryContent(Object label) {
    return '\"$label\" se eliminará de la memoria del agente.';
  }

  @override
  String get install => 'Instalar';

  @override
  String get noProjects => 'Sin proyectos';

  @override
  String get noSessionsInProject => 'Sin sesiones';

  @override
  String get tools => 'Herramientas';

  @override
  String get commands => 'Comandos';

  @override
  String get config => 'Configuración';

  @override
  String get plugins => 'Plugins';

  @override
  String get thisServerReportsNothing =>
      'Este servidor aún no reporta información sobre esta sesión.';

  @override
  String get readOnlyConfigNote =>
      'Solo lectura: los cambios afectan a todo el servidor.';

  @override
  String get maintenanceNote => 'Mantenimiento — afecta a todas las sesiones';

  @override
  String reloadTargetTitle(Object target) {
    return '¿Recargar $target?';
  }

  @override
  String get reloadTargetMessage =>
      'Esto cambiará el servidor para todas las sesiones.';

  @override
  String get continueAction => 'Continuar';

  @override
  String get typeAMessage => 'Escribe un mensaje...';

  @override
  String get send => 'Enviar';

  @override
  String get stopTurn => 'Detener';

  @override
  String get thinking => 'Pensando...';

  @override
  String thinkingTime(Object seconds) {
    return 'Pensó durante ${seconds}s';
  }

  @override
  String get copy => 'Copiar';

  @override
  String get copied => 'Copiado';

  @override
  String get retry => 'Reintentar';

  @override
  String get edit => 'Editar';

  @override
  String get sessionActions => 'Acciones de sesión';

  @override
  String get undoLastExchange => 'Deshacer el último intercambio';

  @override
  String get fileCheckpoints => 'Puntos de control de archivos…';

  @override
  String get journeyWhatItLearned => 'Trayectoria — lo que aprendió…';

  @override
  String get toolsetsSkillsPlugins => 'Herramientas, habilidades, plugins…';

  @override
  String get findInConversation => 'Buscar en la conversación…';

  @override
  String get copyTranscript => 'Copiar transcripción';

  @override
  String get branchSession => 'Crear rama…';

  @override
  String get usageAndContext => 'Uso y contexto…';

  @override
  String get typeACommand => 'Escriba un comando…';

  @override
  String nothingMatches(Object query) {
    return 'No hay coincidencias para “$query”';
  }

  @override
  String get actOnRunningTurn => 'Actuar en el turno en ejecución';

  @override
  String get steerThisTurn => 'Guiar este turno';

  @override
  String get redirectThisTurn => 'Redirigir este turno';

  @override
  String get workingDirectoryTitle => 'Directorio de trabajo';

  @override
  String get workingDirectoryDesc =>
      'Una ruta en el servidor que ejecuta el agente, no en esta Mac. Los adjuntos y referencias @ se resuelven respecto a ella.';

  @override
  String get set => 'Establecer';

  @override
  String get nothingToUndo => 'Nada que deshacer';

  @override
  String removedMessages(Object count) {
    return 'Se eliminaron $count mensaje(s)';
  }

  @override
  String copiedCharacters(Object count) {
    return 'Se copiaron $count caracteres';
  }

  @override
  String get branchFailed => 'Error al crear la rama';

  @override
  String branchedTo(Object id) {
    return 'Rama creada en $id';
  }

  @override
  String get sessionUsage => 'Uso de la sesión';

  @override
  String get sessions => 'Sesiones';

  @override
  String get chat => 'Chat';

  @override
  String get panels => 'Paneles';

  @override
  String get messaging => 'Mensajería';

  @override
  String get artifacts => 'Artefactos';

  @override
  String get kanban => 'Kanban';

  @override
  String get photo => 'Foto';

  @override
  String get library => 'Biblioteca';

  @override
  String get file => 'Archivo';

  @override
  String get video => 'Video';

  @override
  String get pasteFromClipboard => 'Pegar desde el portapapeles';

  @override
  String get referencePathOnServer => 'Referenciar una ruta en el servidor';

  @override
  String get queueForAfterThisTurn =>
      'Poner en cola para después de este turno';

  @override
  String get attachSomething => 'Adjuntar algo';

  @override
  String get rename => 'Renombrar…';

  @override
  String get compressHistory => 'Comprimir historial';

  @override
  String get deleteSessionTitle => 'Eliminar…';

  @override
  String get renameSession => 'Renombrar sesión';

  @override
  String get compressHistoryQuestion => '¿Comprimir historial?';

  @override
  String compressHistoryDesc(Object label) {
    return 'Los mensajes antiguos en \"$label\" se resumirán para recuperar contexto. Esto no se puede deshacer.';
  }

  @override
  String get deleteSessionQuestion => '¿Eliminar sesión?';

  @override
  String deleteSessionDesc(Object count, Object label) {
    return '\"$label\" y sus $count mensajes se eliminarán permanentemente.';
  }

  @override
  String get holdToDelete => 'Mantener para eliminar';

  @override
  String get deleted => 'Eliminado';

  @override
  String get showSessions => 'Mostrar sesiones';

  @override
  String get hideSessions => 'Ocultar sesiones';

  @override
  String get appearanceSystem => 'Apariencia: sistema';

  @override
  String get appearanceLight => 'Apariencia: claro';

  @override
  String get appearanceDark => 'Apariencia: oscuro';

  @override
  String get modelForThisSession => 'Modelo para esta sesión';

  @override
  String get requeryProviders => 'Volver a consultar proveedores';

  @override
  String get noModelList => 'Este servidor no ofreció una lista de modelos.';

  @override
  String get noCredential => 'sin credenciales';

  @override
  String get composerSuggestionResume => 'Continuar la última tarea';

  @override
  String get composerSuggestionStatus => 'Comprobar la sesión actual';

  @override
  String get composerSuggestionRelease => 'Escribir una nota de la versión';
}
