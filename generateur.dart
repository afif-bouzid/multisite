import 'dart:io';

void main() async {
  // --- CONFIGURATION ---
  final Directory projectRoot = Directory.current; // Dossier actuel
  final File outputFile = File('project_context.txt');

  // Dossiers et fichiers à ignorer absolument
  final List<String> ignoredPatterns = [
    '.git', '.dart_tool', '.idea', 'build', 'ios', 'android', 'web',
    'linux', 'macos', 'windows', 'test',
    '.fvm', '.github'
  ];

  // Extensions de fichiers à lire (Code uniquement)
  final List<String> allowedExtensions = ['.dart', '.yaml', '.xml', '.gradle'];

  final StringBuffer buffer = StringBuffer();

  print('🚀 Démarrage de la génération du contexte...');

  // 1. GÉNÉRATION DE L'ARBORESCENCE (VUE D'ENSEMBLE)
  buffer.writeln('##################################################');
  buffer.writeln('# 📂 STRUCTURE DU PROJET (ARBORESCENCE)');
  buffer.writeln('##################################################');
  buffer.writeln('.');
  await _generateTree(projectRoot, '', buffer, ignoredPatterns);
  buffer.writeln('\n'); // Espace

  // 2. LECTURE DES FICHIERS (CONTENU)
  print('📝 Lecture des fichiers...');

  // On inclut d'abord pubspec.yaml car c'est le plus important pour le contexte
  final File pubspec = File('${projectRoot.path}/pubspec.yaml');
  if (await pubspec.exists()) {
    await _appendFileContent(pubspec, buffer);
  }

  // Parcours récursif pour le dossier lib/
  final Directory libDir = Directory('${projectRoot.path}/lib');
  if (await libDir.exists()) {
    await _processDirectoryContents(libDir, buffer, ignoredPatterns, allowedExtensions);
  } else {
    print('⚠️ Attention: Dossier "lib" introuvable.');
  }

  // Écriture finale
  await outputFile.writeAsString(buffer.toString());

  print('--------------------------------------------------');
  print('✅ Succès ! Fichier généré : \"${outputFile.path}\"');
  print('Taille totale : ${(await outputFile.length() / 1024).toStringAsFixed(2)} KB');
}

/// Génère l'arborescence visuelle récursivement
Future<void> _generateTree(
    Directory dir,
    String prefix,
    StringBuffer buffer,
    List<String> ignored
    ) async {
  try {
    // Lister et trier : Dossiers d'abord, puis fichiers
    List<FileSystemEntity> entities = await dir.list().toList();

    // Filtrage
    entities = entities.where((e) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      return !ignored.contains(name) && !name.startsWith('.');
    }).toList();

    // Tri alphabétique (Dossiers en premier pour la propreté)
    entities.sort((a, b) {
      final aName = a.uri.pathSegments.last;
      final bName = b.uri.pathSegments.last;
      if (a is Directory && b is File) return -1;
      if (a is File && b is Directory) return 1;
      return aName.compareTo(bName);
    });

    for (var i = 0; i < entities.length; i++) {
      final entity = entities[i];
      final isLast = i == entities.length - 1;
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;

      buffer.writeln('$prefix${isLast ? '└── ' : '├── '}$name');

      if (entity is Directory) {
        await _generateTree(
            entity,
            '$prefix${isLast ? '    ' : '│   '}',
            buffer,
            ignored
        );
      }
    }
  } catch (e) {
    // Ignorer les erreurs d'accès
  }
}

/// Parcourt les dossiers pour lire le contenu
Future<void> _processDirectoryContents(
    Directory dir,
    StringBuffer buffer,
    List<String> ignored,
    List<String> extensions
    ) async {
  await for (final FileSystemEntity entity in dir.list(recursive: true)) {
    if (entity is File) {
      final path = entity.path;
      final name = entity.uri.pathSegments.last;

      // Filtres
      if (ignored.any((pattern) => path.contains(pattern))) continue;
      if (!extensions.any((ext) => path.endsWith(ext))) continue;

      // Ignorer les fichiers générés
      if (name.endsWith('.g.dart') || name.endsWith('.freezed.dart')) continue;

      await _appendFileContent(entity, buffer);
      print('  -> Ajouté : ${entity.path.split('/').last}');
    }
  }
}

/// Ajoute le contenu d'un fichier au buffer
Future<void> _appendFileContent(File file, StringBuffer buffer) async {
  try {
    String content = await file.readAsString();

    // Nettoyage (Commentaires & Lignes vides)
    String cleanContent = _removeComments(content);
    cleanContent = cleanContent.replaceAll(RegExp(r'\n\s*\n'), '\n');

    buffer.writeln('==================================================');
    buffer.writeln('FILE PATH: ${file.path.substring(Directory.current.path.length + 1)}'); // Chemin relatif
    buffer.writeln('==================================================');
    buffer.writeln(cleanContent);
    buffer.writeln('\n');
  } catch (e) {
    print('⚠️ Erreur lecture ${file.path}');
  }
}

/// Retire les commentaires Dart (// et /* */)
String _removeComments(String source) {
  final RegExp commentRegex = RegExp(r'(\/\*[\s\S]*?\*\/)|(\/\/.*)');
  return source.replaceAll(commentRegex, '');
}