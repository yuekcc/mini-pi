module version @feat(RELEASE);

$exec("bash", {"../scripts/version.sh"});

module version @feat(!RELEASE);

const String VERSION = "1.0.0";
