import 'dart:io';

void main() async {
  final outputFile = File('tout_le_code_de_la_caisse.txt');
  final buffer = StringBuffer();

  // -----------------------------------------------------------
  // CONFIGURATION
  // -----------------------------------------------------------
  // Mets à true SI ET SEULEMENT SI tu as beaucoup de "code mort"
  // Sinon, laisse à false, Gemini comprendra mieux ton projet.
  const bool removeComments = true;
  // -----------------------------------------------------------

  print('Génération en cours...');

  buffer.writeln('<project_root>');

  // 1. Pubspec (Toujours garder intact)
  await _addFileToBuffer(File('pubspec.yaml'), buffer, false);

  // 2. Dossier lib
  final libDir = Directory('lib');
  if (await libDir.exists()) {
    await for (final entity in libDir.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        await _addFileToBuffer(entity, buffer, removeComments);
      }
    }
  }

  buffer.writeln('</project_root>');

  await outputFile.writeAsString(buffer.toString());
  print('✅ Fichier "tout_le_code.txt" généré avec succès !');
}

Future<void> _addFileToBuffer(File file, StringBuffer buffer, bool cleanComments) async {
  if (!await file.exists()) return;

  try {
    final relativePath = file.path.replaceAll('\\', '/');
    buffer.writeln('  <file path="$relativePath">');

    List<String> lines = await file.readAsLines();

    for (var line in lines) {
      // Si on veut nettoyer, on ignore les lignes qui ne sont QUE des commentaires
      // On garde quand même les commentaires en fin de ligne de code (ex: int a = 1; // info)
      if (cleanComments) {
        String trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
          continue;
        }
        // On supprime aussi les lignes vides inutiles en mode nettoyage
        if (trimmed.isEmpty) continue;
      }
      buffer.writeln(line);
    }

    buffer.writeln('  </file>');
    buffer.writeln('');
  } catch (e) {
    print('Erreur sur ${file.path}: $e');
  }
}