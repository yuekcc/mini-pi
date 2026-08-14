module version @feat(RELEASE);

$exec("bash", {"../scripts/version.sh"});

module version @feat(!RELEASE);

const String VERSION = "2.0.0";
