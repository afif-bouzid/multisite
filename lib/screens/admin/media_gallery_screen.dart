import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Assurez-vous d'avoir ce package
import 'package:cached_network_image/cached_network_image.dart'; // Assurez-vous d'avoir ce package
import '../../core/repository/repository.dart';
import '../../models.dart';

class MediaGalleryScreen extends StatefulWidget {
  final String franchisorId;

  const MediaGalleryScreen({super.key, required this.franchisorId});

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  final FranchiseRepository _repo = FranchiseRepository();
  bool _isLoading = false;

  /// Fonction pour ouvrir le dialogue d'ajout de média
  Future<void> _showAddMediaDialog() async {
    final nameController = TextEditingController();
    String selectedType = 'image';
    XFile? selectedFile;
    XFile? selectedThumb; // Pour les vidéos (optionnel)

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Ajouter un contenu"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: "Nom de la campagne / Média",
                      hintText: "Ex: Promo Été 2024",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    items: const [
                      DropdownMenuItem(value: 'image', child: Text("Image")),
                      DropdownMenuItem(value: 'video', child: Text("Vidéo")),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedType = val!;
                        selectedFile = null; // Reset file on type change
                      });
                    },
                    decoration: const InputDecoration(labelText: "Type de média"),
                  ),
                  const SizedBox(height: 20),

                  // Sélection du Fichier Principal
                  OutlinedButton.icon(
                    icon: Icon(selectedType == 'image' ? Icons.image : Icons.videocam),
                    label: Text(selectedFile == null
                        ? "Sélectionner le fichier"
                        : "Fichier sélectionné !"),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: selectedFile != null ? Colors.green : null
                    ),
                    onPressed: () async {
                      final picker = ImagePicker();
                      final XFile? file;
                      if (selectedType == 'image') {
                        file = await picker.pickImage(source: ImageSource.gallery);
                      } else {
                        file = await picker.pickVideo(source: ImageSource.gallery);
                      }
                      if (file != null) {
                        setDialogState(() => selectedFile = file);
                      }
                    },
                  ),

                  // Optionnel : Sélection Miniature pour Vidéo
                  if (selectedType == 'video') ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.image_search),
                      label: Text(selectedThumb == null
                          ? "Ajouter une miniature (Optionnel)"
                          : "Miniature sélectionnée"),
                      onPressed: () async {
                        final file = await ImagePicker().pickImage(source: ImageSource.gallery);
                        if (file != null) {
                          setDialogState(() => selectedThumb = file);
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Annuler")
              ),
              ElevatedButton(
                onPressed: (selectedFile == null || nameController.text.isEmpty)
                    ? null
                    : () async {
                  Navigator.pop(context); // Ferme le dialog
                  _uploadMedia(
                      nameController.text,
                      selectedType,
                      selectedFile!,
                      selectedThumb
                  );
                },
                child: const Text("Uploader"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _uploadMedia(String name, String type, XFile file, XFile? thumb) async {
    setState(() => _isLoading = true);
    try {
      await _repo.addMasterMedia(
        name: name,
        type: type,
        file: file,
        thumbnailFile: thumb,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Média ajouté avec succès !"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Erreur upload: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lors de l'upload : $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Médiathèque Borne (Franchiseur)"),
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _showAddMediaDialog,
        label: const Text("Ajouter"),
        icon: const Icon(Icons.add_photo_alternate),
        backgroundColor: const Color(0xFF502314),
      ),
      body: Stack(
        children: [
          StreamBuilder<List<KioskMedia>>(
            stream: _repo.getAvailableKioskMedias(widget.franchisorId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Erreur: ${snapshot.error}"));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final medias = snapshot.data!;

              if (medias.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.perm_media_outlined, size: 60, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("Aucun média disponible.\nAjoutez-en pour vos franchisés.", textAlign: TextAlign.center),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: medias.length,
                itemBuilder: (context, index) {
                  final media = medias[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _buildMediaPreview(media),
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.white,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    media.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    media.type.toUpperCase(),
                                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: CircleAvatar(
                            backgroundColor: Colors.white,
                            radius: 16,
                            child: IconButton(
                              icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                              onPressed: () => _confirmDelete(media),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview(KioskMedia media) {
    if (media.type == 'image') {
      return CachedNetworkImage(
        imageUrl: media.url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.image))),
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
      );
    } else {
      // Pour la vidéo, on affiche la miniature ou une icône
      if (media.thumbnailUrl != null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(imageUrl: media.thumbnailUrl!, fit: BoxFit.cover),
            const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 48)),
          ],
        );
      }
      return Container(
        color: Colors.black87,
        child: const Center(child: Icon(Icons.videocam, color: Colors.white, size: 48)),
      );
    }
  }

  void _confirmDelete(KioskMedia media) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer ?"),
        content: Text("Voulez-vous vraiment supprimer '${media.name}' ?\nCela le retirera de toutes les bornes qui l'utilisent."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Non")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _repo.deleteMasterMedia(media.id);
            },
            child: const Text("Oui, Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}