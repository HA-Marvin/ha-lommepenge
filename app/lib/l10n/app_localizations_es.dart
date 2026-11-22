// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get add => 'Añadir';

  @override
  String get name => 'Nombre';

  @override
  String get nameRequired => 'El nombre es obligatorio.';

  @override
  String get unknownTask => 'Tarea desconocida';

  @override
  String get unknownChild => 'Niño desconocido';

  @override
  String confirmDelete(Object name) {
    return '¿Seguro que quieres eliminar \"$name\"?';
  }

  @override
  String get language => 'Idioma';

  @override
  String get chooseLanguageTitle => 'Elige el idioma';

  @override
  String get chooseLanguageBody =>
      'Elige el idioma de la app. Puedes cambiarlo más tarde.';

  @override
  String get continueButton => 'Continuar';

  @override
  String get connectTitle => 'Conectar con Home Assistant';

  @override
  String get connectInstructions =>
      'Añade el dispositivo en Home Assistant: Ajustes → Dispositivos y servicios → Lommepenge → Añadir dispositivo. Elige un nombre y un rol, e introduce el código que muestra Home Assistant.';

  @override
  String get codeLabel => 'Código de Home Assistant';

  @override
  String get codeHint => 'p. ej. K7M2QDXA';

  @override
  String get addressLabel => 'Dirección de Home Assistant';

  @override
  String get addressHint => 'p. ej. 192.168.1.10:8123';

  @override
  String get searchingForHa => 'Buscando Home Assistant en la red...';

  @override
  String foundHa(Object name) {
    return 'Encontrado: $name';
  }

  @override
  String get haNotFound =>
      'No se encontró automáticamente: escribe la dirección. Aparece en la página de descarga de la app en Home Assistant.';

  @override
  String get searchAgain => 'Buscar de nuevo';

  @override
  String get connectButton => 'Conectar';

  @override
  String get scanQrInstead => 'Escanear código QR en su lugar';

  @override
  String get scanQrTitle => 'Escanear código QR';

  @override
  String get scanQrHint =>
      'Apunta la cámara al código QR en Home Assistant (Lommepenge → Añadir dispositivo).';

  @override
  String get parentPinTitle => 'PIN de padres';

  @override
  String get pinPrompt => 'Introduce el PIN para entrar en el modo padres.';

  @override
  String get pinLabel => 'PIN';

  @override
  String get wrongPin => 'PIN incorrecto. Inténtalo de nuevo.';

  @override
  String get unlock => 'Desbloquear';

  @override
  String get timesAndLimits => 'Horarios y límites';

  @override
  String get timesAndLimitsHint =>
      'También se puede cambiar desde Home Assistant. Toca para cambiar.';

  @override
  String get defaultDeadline => 'Hora límite predeterminada';

  @override
  String get defaultDeadlineHelp =>
      'Para tareas obligatorias sin hora límite propia.';

  @override
  String get restrictionFrom => 'Bloqueo desde';

  @override
  String get restrictionFromHelp =>
      'Las tabletas pueden bloquearse como muy pronto a partir de esta hora.';

  @override
  String get restrictionUntil => 'Bloqueo hasta';

  @override
  String get restrictionUntilHelp =>
      'Después de esta hora se quita el bloqueo.';

  @override
  String get pauseTime => 'Tiempo de pausa';

  @override
  String get pauseTimeHelp =>
      'Tiempo de espera antes de desbloquear la tableta cuando una tarea se hizo tarde.';

  @override
  String get warningBeforeDeadline => 'Aviso antes del límite';

  @override
  String get warningBeforeDeadlineHelp =>
      'Cuánto tiempo antes del límite se avisa al niño.';

  @override
  String get winterFromWeek => 'Invierno desde la semana';

  @override
  String get winterToWeek => 'Invierno hasta la semana';

  @override
  String get winterHelp =>
      'Se usa para listas de equipaje (p. ej. zapatillas de casa).';

  @override
  String get minutesUnit => 'min';

  @override
  String get resetToDefaults => 'Restablecer valores predeterminados';

  @override
  String get restrictionToday => 'Bloqueo hoy';

  @override
  String get liftedForToday => 'Quitado por hoy';

  @override
  String get restricted => 'Bloqueada';

  @override
  String get overdueOutsideWindow =>
      'Atrasada, pero fuera del horario de bloqueo';

  @override
  String get notRestricted => 'No bloqueada';

  @override
  String get liftToday => 'Quitar hoy';

  @override
  String get roleFamilyScreen => 'Pantalla familiar';

  @override
  String get roleParentPhone => 'Móvil de un padre';

  @override
  String deviceSubtitle(Object role, Object version) {
    return '$role · versión de la app $version';
  }

  @override
  String get notConnected => 'No conectado';

  @override
  String get notFetchedYet => 'Aún no descargado';

  @override
  String lastUpdatedAt(Object time) {
    return 'Última actualización a las $time';
  }

  @override
  String get addDevicesHint =>
      'Los dispositivos nuevos se añaden en Home Assistant en Lommepenge → Añadir dispositivo. También se eliminan allí.';

  @override
  String get forgetConnection => 'Olvidar la conexión en este dispositivo';

  @override
  String get forgetConnectionTitle => '¿Olvidar la conexión?';

  @override
  String get forgetConnectionBody =>
      'El dispositivo deberá conectarse de nuevo con un código nuevo de Home Assistant. Elimínalo también en Lommepenge en Home Assistant si ya no se va a usar.';

  @override
  String get forget => 'Olvidar';

  @override
  String get noChildrenYet => 'Aún no hay niños. Toca + para crear un niño.';

  @override
  String get rename => 'Renombrar';

  @override
  String get addChild => 'Añadir niño';

  @override
  String get renameChild => 'Renombrar niño';

  @override
  String get deleteChild => 'Eliminar niño';

  @override
  String get parentMode => 'Modo padres';

  @override
  String get switchToChildMode => 'Cambiar al modo niño';

  @override
  String get tabTasks => 'Tareas';

  @override
  String get tabChildren => 'Niños';

  @override
  String get tabApprovals => 'Aprobaciones';

  @override
  String get tabOverview => 'Resumen';

  @override
  String get tabHistory => 'Historial';

  @override
  String get tabSettings => 'Ajustes';

  @override
  String get noTasksYet => 'Aún no hay tareas.';

  @override
  String deadlineAt(Object time) {
    return 'límite $time';
  }

  @override
  String get inCalendar => 'en el calendario';

  @override
  String get deleteTask => 'Eliminar tarea';

  @override
  String get noPendingApprovals => 'No hay tareas pendientes de aprobación.';

  @override
  String get late => 'tarde';

  @override
  String get approve => 'Aprobar';

  @override
  String get reject => 'Rechazar';

  @override
  String get adjustBalance => 'Ajustar saldo';

  @override
  String get adjustBalanceHelp =>
      'Úsalo para corregir un saldo incorrecto, p. ej. después de reinstalar. El importe puede ser negativo.';

  @override
  String get child => 'Niño';

  @override
  String amountSigned(Object currency) {
    return 'Importe ($currency, +/-)';
  }

  @override
  String get amountNonZero => 'Introduce un importe distinto de 0.';

  @override
  String get reason => 'Motivo';

  @override
  String get reasonRequired => 'El motivo es obligatorio.';

  @override
  String balanceAdjustedBy(Object amount) {
    return 'Saldo ajustado en $amount.';
  }

  @override
  String get earnedNotPaidOut => 'Ganado, sin pagar';

  @override
  String get paidOutTotal => 'Pagado en total';

  @override
  String get markAsPaidOut => 'Marcar como pagado';

  @override
  String confirmPayout(Object amount, Object name) {
    return 'Vas a marcar $amount como pagado a $name. Después este saldo se pondrá a cero. ¿Continuar?';
  }

  @override
  String get yesPayOut => 'Sí, pagar';

  @override
  String get noCompletedTasksYet => 'Aún no hay tareas completadas.';

  @override
  String balanceAdjustment(Object note) {
    return 'Ajuste de saldo: $note';
  }

  @override
  String get editTask => 'Editar tarea';

  @override
  String get newTask => 'Nueva tarea';

  @override
  String get taskTitle => 'Título';

  @override
  String get titleRequired => 'El título es obligatorio.';

  @override
  String get descriptionOptional => 'Descripción (opcional)';

  @override
  String amountLabel(Object currency) {
    return 'Importe ($currency)';
  }

  @override
  String get amountInvalid => 'Introduce un importe válido (0 o más).';

  @override
  String get recurrence => 'Repetición';

  @override
  String get recurrenceOnce => 'Una vez';

  @override
  String get recurrenceDaily => 'Diaria';

  @override
  String get recurrenceWeekly => 'Semanal';

  @override
  String get recurrenceUnlimited => 'Ilimitada';

  @override
  String get weeklyDiscontinued =>
      'Ya no disponible: elige \"Diaria\" y ajusta el plan semanal al día o días que quieras.';

  @override
  String get unlimitedHelp =>
      'Se puede hacer varias veces al día; solo se bloquea mientras una realización espera aprobación.';

  @override
  String get weekPlan => 'Plan semanal';

  @override
  String get weekPlanHelp =>
      'Elige qué días está activa la tarea, p. ej. solo martes y jueves. Por defecto todos los días.';

  @override
  String get allDays => 'Todos los días';

  @override
  String get weekdays => 'Entre semana';

  @override
  String get weekend => 'Fin de semana';

  @override
  String get assignTo => 'Asignar a';

  @override
  String get assignToHelp =>
      'Elige a qué niños se aplica la tarea. \"Todos los niños\" se aplica de forma dinámica, también a los niños que se añadan después.';

  @override
  String get allChildren => 'Todos los niños';

  @override
  String get mandatoryTask => 'Tarea obligatoria';

  @override
  String get mandatoryTaskHelp =>
      'Se muestra claramente marcada como \"hay que hacerla\" en lugar de \"se puede hacer\".';

  @override
  String get timeOfDay => 'Hora';

  @override
  String timeHelpMandatory(Object time) {
    return 'Después del límite la tarea cuenta como atrasada. Sin límite propio se usa el límite predeterminado de la familia ($time).';
  }

  @override
  String get timeHelpOptional =>
      'Opcional. El límite solo se sigue en las tareas obligatorias.';

  @override
  String get fromLabel => 'Desde';

  @override
  String get deadline => 'Límite';

  @override
  String get none => 'Ninguna';

  @override
  String get defaultLabel => 'Predeterminado';

  @override
  String get removeTime => 'Quitar hora';

  @override
  String get showInCalendar => 'Mostrar en el calendario familiar';

  @override
  String get showInCalendarHelp =>
      'La tarea se convierte en una cita del calendario familiar cuando el calendario esté configurado.';

  @override
  String get saving => 'Guardando...';

  @override
  String get saveTask => 'Guardar tarea';

  @override
  String get sentForApproval => '¡Enviado para aprobación!';

  @override
  String get noTasksAskParent =>
      'Aún no hay tareas. Pide a un padre que cree algunas en el modo padres.';

  @override
  String hiChild(Object name) {
    return '¡Hola, $name!';
  }

  @override
  String get fetchingYourTasks => 'Cargando tus tareas...';

  @override
  String get noTasksRightNow => 'Ahora mismo no tienes tareas.';

  @override
  String get noChildrenCreateInParentMode =>
      'Aún no hay niños. Créalos en el modo padres.';

  @override
  String get noTasks => 'Sin tareas.';

  @override
  String get restrictedTitle => 'Los juegos y YouTube están bloqueados';

  @override
  String restrictedDoFirst(Object tasks) {
    return 'Haz primero: $tasks. Luego se desbloquean de nuevo.';
  }

  @override
  String restrictedLatePause(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other:
          'La tarea se hizo tarde, así que faltan $minutes minutos para que tu tableta se desbloquee.',
      one:
          'La tarea se hizo tarde, así que falta 1 minuto para que tu tableta se desbloquee.',
    );
    return '$_temp0';
  }

  @override
  String get behindTitle => 'Vas con retraso';

  @override
  String behindBody(Object tasks, Object time) {
    return '$tasks ya debería estar hecho. Los juegos y YouTube se bloquean a partir de las $time si no está hecho.';
  }

  @override
  String reminderTitle(Object task) {
    return 'Recuerda: $task';
  }

  @override
  String reminderBody(Object time) {
    return 'Tiene que estar hecho antes de las $time; si no, se bloquean los juegos y YouTube.';
  }

  @override
  String reasonOverdue(Object tasks) {
    return 'Falta: $tasks';
  }

  @override
  String reasonOverdueTask(Object title, Object due) {
    return '$title (límite $due)';
  }

  @override
  String reasonLate(Object time) {
    return 'La tarea se hizo tarde - se desbloquea a las $time';
  }

  @override
  String thisWeekAmount(Object amount) {
    return 'Esta semana: $amount';
  }

  @override
  String completedThisWeek(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Esta semana: $count tareas completadas',
      one: 'Esta semana: 1 tarea completada',
    );
    return '$_temp0';
  }

  @override
  String get syncStatus => 'Estado de sincronización';

  @override
  String get connectedToHa => 'Conectado a Home Assistant.';

  @override
  String get mustBeDone => 'Hay que hacerla';

  @override
  String fromTime(Object time) {
    return 'desde las $time';
  }

  @override
  String byTime(Object time) {
    return 'antes de las $time';
  }

  @override
  String get notAssigned => 'No está asignada a ningún niño de la familia.';

  @override
  String get done => 'Hecho';

  @override
  String get statusAvailable => 'Lista para hacer';

  @override
  String get statusPending => 'Esperando aprobación';

  @override
  String get statusDoneToday => 'Hecha hoy - disponible de nuevo mañana';

  @override
  String get statusDoneThisWeek =>
      'Hecha esta semana - pronto disponible de nuevo';

  @override
  String statusDoneThisWeekUntil(Object date) {
    return 'Hecha esta semana - disponible de nuevo ($date)';
  }

  @override
  String get statusCompleted => 'Completada';

  @override
  String get statusNotScheduled => 'Hoy no está en el plan semanal';

  @override
  String statusNotScheduledUntil(Object date) {
    return 'Hoy no está en el plan semanal ($date)';
  }

  @override
  String newVersionReady(Object version) {
    return 'La nueva versión $version está lista.';
  }

  @override
  String get update => 'Actualizar';

  @override
  String get notLommepengeLink =>
      'No es un enlace de Lommepenge de Home Assistant.';

  @override
  String get enterAddressAndCode =>
      'Escribe la dirección de Home Assistant y el código.';

  @override
  String get tabletAlreadyConnected =>
      'Esta tableta ya está conectada. Reinstala la app para conectarla de nuevo.';

  @override
  String get unexpectedResponse => 'Respuesta inesperada de Home Assistant.';

  @override
  String get notConnectedYet => 'Aún no está conectado a Home Assistant.';

  @override
  String get deviceRemoved =>
      'El dispositivo se eliminó en Home Assistant. Conéctalo de nuevo con un código nuevo de Home Assistant (Lommepenge → Añadir dispositivo).';

  @override
  String get noConnectionRetryLater =>
      'Sin conexión con Home Assistant. Se reintentará más tarde.';

  @override
  String get updateNotificationTitle => 'Nueva versión de Lommepenge';

  @override
  String updateNotificationBody(Object version) {
    return 'La versión $version está lista. Abre la app para actualizar.';
  }

  @override
  String get updatesChannel => 'Actualizaciones';

  @override
  String get allowUnknownApps =>
      'Permite \"Instalar aplicaciones desconocidas\" para Lommepenge y vuelve a tocar Actualizar.';

  @override
  String get downloadCorrupt =>
      'El archivo descargado estaba dañado. Inténtalo de nuevo.';

  @override
  String installing(Object version) {
    return 'Instalando la versión $version...';
  }

  @override
  String installFailed(Object error) {
    return 'No se pudo instalar: $error';
  }

  @override
  String get installationFailed => 'La instalación ha fallado.';

  @override
  String haRejectedConnection(Object status) {
    return 'Home Assistant rechazó la conexión ($status).';
  }

  @override
  String get cannotReachHaHomeNetwork =>
      'No se puede conectar con Home Assistant. ¿Está el dispositivo en la red de casa?';

  @override
  String get haTimeout => 'Home Assistant no respondió a tiempo.';

  @override
  String unexpectedError(Object error) {
    return 'Error inesperado: $error';
  }

  @override
  String haUpdateFailed(Object status) {
    return 'Home Assistant no pudo entregar la actualización ($status).';
  }

  @override
  String get cannotReachHa => 'No se puede conectar con Home Assistant.';

  @override
  String updateDownloadFailed(Object error) {
    return 'No se pudo descargar la actualización: $error';
  }

  @override
  String get deviceNoLongerConnected =>
      'El dispositivo ya no está conectado a Home Assistant.';

  @override
  String haError(Object status) {
    return 'Home Assistant respondió con un error ($status).';
  }

  @override
  String get noConnectionCheckNetwork =>
      'Sin conexión con Home Assistant. Comprueba que el dispositivo está en la red de casa.';

  @override
  String get haTimeoutRetry =>
      'Home Assistant no respondió a tiempo. Se reintentará más tarde.';

  @override
  String get errChildNameEmpty => 'El nombre del niño no puede estar vacío.';

  @override
  String get errChildNotFound => 'El niño ya no existe.';

  @override
  String get errAdjustmentNote => 'Un ajuste de saldo debe tener una nota.';

  @override
  String get errTaskNotFound => 'La tarea ya no existe.';

  @override
  String get errTaskNotAssigned => 'La tarea no está asignada a este niño.';

  @override
  String get errTaskNotAvailable =>
      'La tarea no se puede marcar como hecha ahora mismo.';

  @override
  String get errCompletionNotFound => 'La realización no existe.';

  @override
  String get errCompletionHandled => 'La realización ya se ha gestionado.';

  @override
  String get errMissingChildId =>
      'La acción no indica a qué niño corresponde (childId).';

  @override
  String get errMissingName => 'A la acción le falta un nombre.';

  @override
  String get errMissingIdOrName => 'A la acción le falta un id o un nombre.';

  @override
  String get errMissingId => 'A la acción le falta un id.';

  @override
  String get errMissingSetting => 'A la acción le falta un ajuste.';

  @override
  String errUnknownAction(Object type) {
    return 'Acción desconocida: $type';
  }

  @override
  String errInvalidTime(Object key, Object value) {
    return 'Hora no válida para $key: $value';
  }

  @override
  String errSettingRange(Object key, Object min, Object max, Object value) {
    return '$key debe estar entre $min y $max: $value';
  }

  @override
  String errUnknownSetting(Object key) {
    return 'Ajuste desconocido: $key';
  }
}
