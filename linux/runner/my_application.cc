#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* color_picker_channel;
  FlMethodChannel* file_opener_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ── GTK color picker method channel ─────────────────────────────────────────

typedef struct {
  FlMethodCall* method_call;
} ColorPickCallbackData;

static void on_color_dialog_response(GtkDialog* dialog, gint response_id,
                                     gpointer user_data) {
  ColorPickCallbackData* data = (ColorPickCallbackData*)user_data;
  if (response_id == GTK_RESPONSE_OK) {
    GdkRGBA color;
    gtk_color_chooser_get_rgba(GTK_COLOR_CHOOSER(dialog), &color);
    // Format as 6-char uppercase hex string (no alpha).
    gchar* hex = g_strdup_printf(
        "%02X%02X%02X",
        (int)(color.red * 255.0 + 0.5),
        (int)(color.green * 255.0 + 0.5),
        (int)(color.blue * 255.0 + 0.5));
    g_autoptr(FlValue) result = fl_value_new_string(hex);
    g_autoptr(FlMethodSuccessResponse) response =
        fl_method_success_response_new(result);
    fl_method_call_respond(data->method_call, FL_METHOD_RESPONSE(response),
                           nullptr);
    g_free(hex);
  } else {
    g_autoptr(FlMethodSuccessResponse) response =
        fl_method_success_response_new(fl_value_new_null());
    fl_method_call_respond(data->method_call, FL_METHOD_RESPONSE(response),
                           nullptr);
  }
  g_object_unref(data->method_call);
  g_free(data);
  gtk_widget_destroy(GTK_WIDGET(dialog));
}

static void color_picker_method_call_handler(FlMethodChannel* channel,
                                             FlMethodCall* method_call,
                                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);

  if (strcmp(fl_method_call_get_name(method_call), "pick") != 0) {
    g_autoptr(FlMethodNotImplementedResponse) response =
        fl_method_not_implemented_response_new();
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    return;
  }

  // Parse initial color from args {"initial": "RRGGBB"}
  FlValue* args = fl_method_call_get_args(method_call);
  const gchar* initial_hex = nullptr;
  if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    FlValue* initial = fl_value_lookup_string(args, "initial");
    if (initial != nullptr && fl_value_get_type(initial) == FL_VALUE_TYPE_STRING) {
      initial_hex = fl_value_get_string(initial);
    }
  }

  GdkRGBA initial_color = {0.5, 0.5, 0.5, 1.0};
  if (initial_hex != nullptr) {
    gchar* hex_with_hash = g_strdup_printf("#%s", initial_hex);
    gdk_rgba_parse(&initial_color, hex_with_hash);
    g_free(hex_with_hash);
  }

  GtkWindow* parent =
      GTK_WINDOW(gtk_application_get_active_window(GTK_APPLICATION(self)));

  GtkWidget* dialog = gtk_color_chooser_dialog_new("Pick Colour", parent);
  gtk_color_chooser_set_rgba(GTK_COLOR_CHOOSER(dialog), &initial_color);
  gtk_color_chooser_set_use_alpha(GTK_COLOR_CHOOSER(dialog), FALSE);

  ColorPickCallbackData* cb_data =
      (ColorPickCallbackData*)g_malloc(sizeof(ColorPickCallbackData));
  cb_data->method_call = FL_METHOD_CALL(g_object_ref(method_call));

  g_signal_connect(dialog, "response",
                   G_CALLBACK(on_color_dialog_response), cb_data);
  gtk_widget_show(dialog);
}

// ── GTK / GIO file opener method channel ────────────────────────────────────
// Uses g_app_info_launch_default_for_uri_async (portal-aware async variant).
// The Dart side must pass a path the host portal can access (e.g. inside
// xdg-download which is shared with --filesystem=xdg-download).

typedef struct {
  FlMethodCall* method_call;
} OpenFilePortalData;

static void on_open_uri_done(GObject* source_object, GAsyncResult* res,
                             gpointer user_data) {
  OpenFilePortalData* data = (OpenFilePortalData*)user_data;
  GError* error = nullptr;
  gboolean ok = g_app_info_launch_default_for_uri_finish(res, &error);
  if (error) {
    g_error_free(error);
  }
  g_autoptr(FlValue) val = fl_value_new_bool(ok);
  g_autoptr(FlMethodSuccessResponse) resp = fl_method_success_response_new(val);
  fl_method_call_respond(data->method_call, FL_METHOD_RESPONSE(resp), nullptr);
  g_object_unref(data->method_call);
  g_free(data);
}

static void file_opener_method_call_handler(FlMethodChannel* channel,
                                            FlMethodCall* method_call,
                                            gpointer user_data) {
  if (strcmp(fl_method_call_get_name(method_call), "open") != 0) {
    g_autoptr(FlMethodNotImplementedResponse) resp =
        fl_method_not_implemented_response_new();
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(resp), nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* path_val =
      (args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP)
          ? fl_value_lookup_string(args, "path")
          : nullptr;

  if (!path_val || fl_value_get_type(path_val) != FL_VALUE_TYPE_STRING) {
    fl_method_call_respond_error(method_call, "BAD_ARG", "Missing path",
                                 nullptr, nullptr);
    return;
  }

  const gchar* path = fl_value_get_string(path_val);
  gchar* uri = g_strdup_printf("file://%s", path);

  OpenFilePortalData* cb_data = g_new(OpenFilePortalData, 1);
  cb_data->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  g_app_info_launch_default_for_uri_async(uri, nullptr, nullptr,
                                          on_open_uri_done, cb_data);
  g_free(uri);
}

// ── Flutter window setup ─────────────────────────────────────────────────────

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "lanis");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "lanis");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Register the color picker method channel.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->color_picker_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.github.lanis-mobile/color_picker",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->color_picker_channel,
      color_picker_method_call_handler,
      self,
      nullptr);

  // Register the file opener method channel.
  self->file_opener_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.github.lanis-mobile/file_opener",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->file_opener_channel,
      file_opener_method_call_handler,
      self,
      nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->color_picker_channel);
  g_clear_object(&self->file_opener_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}

