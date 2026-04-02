module tools;

import std::io;
import std::io::path;
import std::collections::list;
import std::collections::object;
import std::encoding::json;

import cmd;

fn String? write(Allocator allocator, String file_path, String content) {
  return write_file(allocator, file_path, content);
}

fn String? write_file(Allocator allocator, String file_path, String content) {
  if (try file::save(file_path, content)) {
    return string::format(allocator, "Saved to %s", file_path);
  }
  return WRITE_FILE_ERROR~;
}

fn String? edit(Allocator allocator, String file_path, String old_text,
                 String new_text) {
  Path? path_obj = path::new(tmem, file_path);
  if (try path_obj) {
    if (try content = file::load_path(tmem, path_obj)) {
      String normalized_content = ((String)content).treplace("\r\n", "\n");
      String normalized_old = old_text.treplace("\r\n", "\n");
      String normalized_new = new_text.treplace("\r\n", "\n");

      String updated = normalized_content
                        .replace(tmem, normalized_old, normalized_new)
                        .copy(allocator);
      return write_file(allocator, file_path, updated);
    }
    return READ_FILE_ERROR~;
  }
  return INVALIDE_FILE_PATH~;
}
