import bash from './bash.json'
import edit from './edit.json'
import find from './find.json'
import grep from './grep.json'
import ls from './ls.json'
import read from './read.json'
import write from './write.json'

import fs from 'node:fs/promises'

const schema = [
    ls,
    grep,
    read,
    find,
    edit,
    write,
    bash
]

await fs.writeFile("../tools_schema.json", JSON.stringify(schema), 'utf-8')