module version @if(!$feature(RELEASE));

const String VERSION = "0.0.1";

module version @if($feature(RELEASE));

$exec("bash", { "version.sh" });


module cli;

import std::io;
import version;

fn void print_help()
{
	io::printfn("%s", HELP);
}

fn void print_version()
{
	io::printfn("mp %s", version::VERSION);
}
