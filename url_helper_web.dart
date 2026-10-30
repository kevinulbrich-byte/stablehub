import 'dart:html' as html;

void removeInviteTokenFromUrl() {
  final cleanUri = Uri.base.replace(
    queryParameters: {
      for (final entry in Uri.base.queryParameters.entries)
        if (entry.key != 'invite_token') entry.key: entry.value,
    },
  );

  html.window.history.replaceState(
    null,
    '',
    cleanUri.toString(),
  );
}
