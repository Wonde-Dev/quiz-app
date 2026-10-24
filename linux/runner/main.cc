#include "my_application.h"

#include <glib.h>
#include <linux/limits.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fstream>
#include <string>

// Ubuntu 24.04 (GNOME 46) moved 'antialiasing', 'hinting', and 'rgba-order'
// from 'org.gnome.settings-daemon.plugins.xsettings' to a deprecated schema.
// GTK3's display initialization directly queries this key from xsettings; when missing,
// GIO aborts the process with GLib-GIO-ERROR.
// We configure GSETTINGS_SCHEMA_DIR to include a patched schema directory.
static void configure_glib_schemas() {
  std::string valid_schema_dir = "";

  // 1. Check bundle data directory relative to executable
  char exe_path[PATH_MAX] = {0};
  ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
  if (len > 0) {
    exe_path[len] = '\0';
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);

    // Check ${exe_dir}/data/glib-2.0/schemas
    g_autofree gchar* bundle_schemas =
        g_build_filename(exe_dir, "data", "glib-2.0", "schemas", nullptr);
    g_autofree gchar* compiled_file =
        g_build_filename(bundle_schemas, "gschemas.compiled", nullptr);
    if (g_file_test(compiled_file, G_FILE_TEST_EXISTS)) {
      valid_schema_dir = bundle_schemas;
    }
  }

  // 2. Check source runner schemas directory (for debug runs)
  if (valid_schema_dir.empty()) {
    const char* runner_schemas =
        "/home/neostack/Documents/Flutter-Project/flutter/quiz_app/linux/runner/schemas";
    g_autofree gchar* runner_compiled =
        g_build_filename(runner_schemas, "gschemas.compiled", nullptr);
    if (g_file_test(runner_compiled, G_FILE_TEST_EXISTS)) {
      valid_schema_dir = runner_schemas;
    }
  }

  // 3. Fallback: create & compile in /tmp/.quiz_app_schemas if not found
  if (valid_schema_dir.empty()) {
    const char* tmp_dir = "/tmp/.quiz_app_schemas";
    g_autofree gchar* tmp_compiled =
        g_build_filename(tmp_dir, "gschemas.compiled", nullptr);
    if (!g_file_test(tmp_compiled, G_FILE_TEST_EXISTS)) {
      mkdir(tmp_dir, 0755);
      // Copy enums if present
      if (g_file_test(
              "/usr/share/glib-2.0/schemas/org.gnome.settings-daemon.enums.xml",
              G_FILE_TEST_EXISTS)) {
        std::ifstream src(
            "/usr/share/glib-2.0/schemas/org.gnome.settings-daemon.enums.xml",
            std::ios::binary);
        std::ofstream dst(
            std::string(tmp_dir) + "/org.gnome.settings-daemon.enums.xml",
            std::ios::binary);
        dst << src.rdbuf();
      }
      // Write xsettings schema
      std::ofstream xml_out(
          std::string(tmp_dir) +
          "/org.gnome.settings-daemon.plugins.xsettings.gschema.xml");
      xml_out << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
              << "<schemalist>\n"
              << "  <schema gettext-domain=\"gnome-settings-daemon\" "
                 "id=\"org.gnome.settings-daemon.plugins.xsettings\" "
                 "path=\"/org/gnome/settings-daemon/plugins/xsettings/\">\n"
              << "    <key name=\"antialiasing\" "
                 "enum=\"org.gnome.settings-daemon.GsdFontAntialiasingMode\"><"
                 "default>'grayscale'</default><summary>Antialiasing</summary>"
                 "<description>Font antialiasing</description></key>\n"
              << "    <key name=\"hinting\" "
                 "enum=\"org.gnome.settings-daemon.GsdFontHinting\"><default>'"
                 "slight'</default><summary>Hinting</summary><description>Font "
                 "hinting</description></key>\n"
              << "    <key name=\"rgba-order\" "
                 "enum=\"org.gnome.settings-daemon.GsdFontRgbaOrder\"><default>"
                 "'rgb'</default><summary>RGBA "
                 "order</summary><description>Font RGBA "
                 "order</description></key>\n"
              << "    <key name=\"disabled-gtk-modules\" "
                 "type=\"as\"><default>[]</default></key>\n"
              << "    <key name=\"enabled-gtk-modules\" "
                 "type=\"as\"><default>[]</default></key>\n"
              << "    <key type=\"a{sv}\" "
                 "name=\"overrides\"><default>{}</default></key>\n"
              << "  </schema>\n"
              << "</schemalist>\n";
      xml_out.close();
      int res = system("glib-compile-schemas /tmp/.quiz_app_schemas >/dev/null 2>&1");
      (void)res;
    }
    if (g_file_test(tmp_compiled, G_FILE_TEST_EXISTS)) {
      valid_schema_dir = tmp_dir;
    }
  }

  // Set GSETTINGS_SCHEMA_DIR
  if (!valid_schema_dir.empty()) {
    std::string new_env = valid_schema_dir;
    const char* cur = g_getenv("GSETTINGS_SCHEMA_DIR");
    if (cur && strlen(cur) > 0) {
      new_env += ":";
      new_env += cur;
    }
    if (new_env.find("/usr/share/glib-2.0/schemas") == std::string::npos) {
      new_env += ":/usr/share/glib-2.0/schemas";
    }
    g_setenv("GSETTINGS_SCHEMA_DIR", new_env.c_str(), TRUE);
  }
}

int main(int argc, char** argv) {
  configure_glib_schemas();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
