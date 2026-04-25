import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/repository/repository.dart';
import '../../models.dart';

class KioskCustomizationScreen extends StatelessWidget {
  final String franchisorId;
  final String franchiseeId;

  const KioskCustomizationScreen({
    super.key,
    required this.franchisorId,
    required this.franchiseeId,
  });

  @override
  Widget build(BuildContext context) {
    final repo = FranchiseRepository();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // Fond gris clair moderne
      appBar: AppBar(
        title: const Text("Personnalisation de la Borne"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête explicatif
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Écran d'Accueil",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Sélectionnez le visuel qui s'affichera sur l'écran de veille de votre borne. "
                  "Ces contenus sont validés par votre franchiseur.",
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              // 1. On écoute la config actuelle pour savoir quel ID est actif
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(franchiseeId)
                  .collection('config')
                  .doc('kiosk_customization')
                  .snapshots(),
              builder: (context, configSnapshot) {
                String? activeMediaId;
                if (configSnapshot.hasData && configSnapshot.data!.exists) {
                  final data =
                      configSnapshot.data!.data() as Map<String, dynamic>;
                  activeMediaId = data['activeMediaId'] as String?;
                }

                return StreamBuilder<List<KioskMedia>>(
                  // 2. On récupère la liste des médias disponibles
                  stream: repo.getAvailableKioskMedias(franchisorId),
                  builder: (context, mediaSnapshot) {
                    if (mediaSnapshot.hasError) {
                      return Center(
                          child: Text("Erreur: ${mediaSnapshot.error}"));
                    }
                    if (!mediaSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final medias = mediaSnapshot.data!;

                    if (medias.isEmpty) {
                      return const Center(
                        child: Text("Aucun thème disponible pour le moment."),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 400, // Cartes assez larges
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 20,
                        mainAxisSpacing: 20,
                      ),
                      itemCount: medias.length,
                      itemBuilder: (context, index) {
                        final media = medias[index];
                        final bool isActive = media.id == activeMediaId;

                        return _buildMediaCard(context, media, isActive, repo);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaCard(BuildContext context, KioskMedia media, bool isActive,
      FranchiseRepository repo) {
    return GestureDetector(
      onTap: () async {
        if (isActive) return;
        await repo.setKioskActiveMedia(franchiseeId, media);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Thème '${media.name}' activé sur la borne !"),
              backgroundColor: const Color(0xFF417228),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? const Color(0xFF417228) : Colors.transparent,
            width: isActive ? 4 : 0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isActive ? 0.2 : 0.05),
              blurRadius: isActive ? 12 : 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
              12), // Un peu moins pour coller à la bordure
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildPreviewContent(media),
                  ),
                  Expanded(
                    flex: 1,
                    child: Container(
                      color: isActive
                          ? const Color(0xFF417228).withOpacity(0.05)
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  media.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isActive
                                        ? const Color(0xFF417228)
                                        : Colors.black,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  media.type == 'video'
                                      ? "Vidéo MP4"
                                      : "Image JPG/PNG",
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          if (isActive)
                            const CircleAvatar(
                              backgroundColor: Color(0xFF417228),
                              radius: 14,
                              child: Icon(Icons.check,
                                  size: 18, color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Badge Type
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        media.type == 'video' ? Icons.videocam : Icons.image,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        media.type.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewContent(KioskMedia media) {
    if (media.type == 'image') {
      return CachedNetworkImage(
        imageUrl: media.url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: Colors.grey[100]),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
      );
    } else {
      if (media.thumbnailUrl != null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
                imageUrl: media.thumbnailUrl!, fit: BoxFit.cover),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 32),
              ),
            ),
          ],
        );
      }
      return Container(
        color: Colors.black87,
        child: const Center(
            child: Icon(Icons.videocam, size: 48, color: Colors.white54)),
      );
    }
  }
}
