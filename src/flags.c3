module version @if(!$feature(RELEASE));

const String VERSION = "0.0.1";

module version @if($feature(RELEASE));

$exec("bash", { "version.sh" });


module flags;

import std::io;
import version;


const String HELP = `mp - a pi coding agent clone, my own coding agent.

flags:
	--agent         指定智能体角色，默认为 default
	--model         指定使用的模型 ID
	--tools         允许使用的工具列表，默认值是 read,bash,edit,write,grep,find,ls
	--headless      设置为非交互模式，未设置 --headless 时默认进入交互模式
	--init-message  指定默认提示词（需要同时设置 --headless），支持 @filename 方式从文件获取提示词
	--help          显示帮助信息
	--version       查看版本号
	--debug         启动 DEBUG 模式

tools:
	- 'read'
	- 'bash'
	- 'edit'
	- 'write'
	- 'grep'
	- 'find'
	- 'ls'
`;


fn void print_help()
{
	io::printfn("%s", HELP);
}

fn void print_version()
{
	io::printfn("mp %s", version::VERSION);
}
