module version @if($feature(RELEASE));

$exec("bash", {"../scripts/version.sh"});

module version @if(!$feature(RELEASE));

const String VERSION = "1.0.0";
