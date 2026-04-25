import 'dart:io';

void main() async {
  // --- CONFIGURATION ---
  final File inputFile = File('project_context.txt');
  // On cible directement le dossier actuel (la racine de ton projet)
  final Directory outputDir = Directory.current;

  if (!await inputFile.exists()) {
    print('❌ Fichier introuvable : ${inputFile.path}');
    return;
  }

  print('🚀 Démarrage de la reconstruction dans le projet actuel...');
  print('⚠️ Attention : Les fichiers existants seront écrasés !');

  final List<String> lines = await inputFile.readAsLines();

  String? currentFilePath;
  StringBuffer currentContent = StringBuffer();

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];

    // Détection de l'en-tête d'un fichier
    if (line.startsWith('FILE PATH: ')) {
      // Si on avait un fichier précédent en mémoire, on le sauvegarde
      if (currentFilePath != null) {
        await _saveFile(
            outputDir.path, currentFilePath, currentContent.toString());
      }

      // Initialisation du nouveau fichier
      currentFilePath = line.replaceFirst('FILE PATH: ', '').trim();
      currentContent = StringBuffer();

      // Ignorer la ligne "==========" juste en dessous
      if (i + 1 < lines.length && lines[i + 1].startsWith('=======')) {
        i++; // Saute la ligne
      }
    }
    // Ignorer la ligne "==========" juste au-dessus du PROCHAIN "FILE PATH:"
    else if (line.startsWith('=======') &&
        i + 1 < lines.length &&
        lines[i + 1].startsWith('FILE PATH: ')) {
      continue;
    }
    // Ajouter le contenu au fichier actuel (s'il y en a un de déclaré)
    else if (currentFilePath != null) {
      currentContent.writeln(line);
    }
  }

  // Sauvegarder le tout dernier fichier lu
  if (currentFilePath != null) {
    await _saveFile(outputDir.path, currentFilePath, currentContent.toString());
  }

  print('--------------------------------------------------');
  print('✅ Reconstruction terminée !');
}

/// Crée les dossiers manquants et écrit le contenu dans le fichier
Future<void> _saveFile(
    String baseDir, String relativePath, String content) async {
  try {
    // relativePath contient déjà 'lib/fichier.dart' ou 'pubspec.yaml'
    final file = File('$baseDir/$relativePath');

    // Création de l'arborescence complète pour ce fichier si elle n'existe pas
    await file.parent.create(recursive: true);

    // Nettoyage des espaces/retours à la ligne en trop à la fin
    await file.writeAsString('${content.trim()}\n');
    print('  -> Restauré/Écrasé : $relativePath');
  } catch (e) {
    print('⚠️ Erreur lors de la restauration de $relativePath : $e');
  }
}
