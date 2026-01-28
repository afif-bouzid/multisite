import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '/models.dart';

class FranchiseeProductCard extends StatelessWidget {
  final MasterProduct product;
  final FranchiseeMenuItem? settings;
  final String? franchiseeId;
  final String? franchisorId;
  final CollectionReference franchiseeMenuRef;
  final VoidCallback onTapCard;
  final Function(bool) onToggleSwitch;
  final VoidCallback onToggleStock;

  const FranchiseeProductCard({
    super.key,
    required this.product,
    required this.settings,
    required this.franchiseeId,
    required this.franchisorId,
    required this.franchiseeMenuRef,
    required this.onTapCard,
    required this.onToggleSwitch,
    required this.onToggleStock,
  });

  @override
  Widget build(BuildContext context) {
    // Récupération des états
    final bool isVisible = settings?.isVisible ?? false;
    final bool isAvailable = settings?.isAvailable ?? true;
    final double price = settings?.price ?? 0.0;

    // --- DISTINCTION VISUELLE ---
    // Si c'est un conteneur, on applique un style "Dossier" (Orange)
    final bool isContainer = product.isContainer;
    final Color cardColor = isContainer ? Colors.orange.shade50 : Colors.white;
    final Color borderColor = isContainer ? Colors.orange.shade200 : Colors.grey.shade200;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: isContainer ? 1.5 : 1),
      ),
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTapCard,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // --- 1. IMAGE OU ICONE ---
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: (product.photoUrl != null && product.photoUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                    imageUrl: product.photoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => _buildFallbackIcon(isContainer),
                  )
                      : _buildFallbackIcon(isContainer),
                ),
              ),
              const SizedBox(width: 16),

              // --- 2. INFORMATIONS PRINCIPALES ---
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF2D3436),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // --- AFFICHAGE PRIX ou LABEL DOSSIER ---
                    if (isContainer)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "DOSSIER / MENU",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      )
                    else
                      Text(
                        "${price.toStringAsFixed(2)} €",
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.blueGrey,
                        ),
                      ),

                    // Petit indicateur si masqué sur la borne mais actif
                    if (isVisible && (settings?.hidePriceOnCard ?? false) && !isContainer)
                      const Text(
                        "Prix masqué sur carte",
                        style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                  ],
                ),
              ),

              // --- 3. ACTIONS (Switch & Stock) ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Switch ON/OFF (Visible)
                  Row(
                    children: [
                      Text(
                        isVisible ? "Actif" : "Inactif",
                        style: TextStyle(
                          fontSize: 12,
                          color: isVisible ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: isVisible,
                        activeColor: isContainer ? Colors.orange : Colors.green,
                        onChanged: onToggleSwitch,
                      ),
                    ],
                  ),

                  // Bouton Stock (Uniquement si visible)
                  if (isVisible)
                    InkWell(
                      onTap: onToggleStock,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAvailable ? Icons.check_circle_outline : Icons.remove_circle_outline,
                              size: 16,
                              color: isAvailable ? Colors.blue : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isAvailable ? "En stock" : "Épuisé",
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isAvailable ? Colors.blue : Colors.red,
                                  fontWeight: FontWeight.w500
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackIcon(bool isContainer) {
    return Center(
      child: Icon(
        isContainer ? Icons.folder_copy_rounded : Icons.fastfood_rounded,
        color: isContainer ? Colors.orange.shade300 : Colors.grey.shade300,
        size: 24,
      ),
    );
  }
}