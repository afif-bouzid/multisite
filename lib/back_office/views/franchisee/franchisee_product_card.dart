import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// Importez vos modèles ici (MasterProduct, FranchiseeMenuItem, etc.)
import '../../../models.dart';
import 'franchisee_composite_overrides_dialog.dart';

class FranchiseeProductCard extends StatelessWidget {
  final MasterProduct product;
  final FranchiseeMenuItem? settings;
  final String? franchiseeId;
  final String? franchisorId;
  final CollectionReference franchiseeMenuRef;
  final Function() onTapCard;
  final Function(bool) onToggleSwitch;
  final Function() onToggleStock;

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
    final isEnabled = settings?.isVisible ?? false;
    final isAvailable = settings?.isAvailable ?? true;
    final hasTimeRestriction = settings?.availableStartTime != null &&
        settings?.availableEndTime != null;
    final isPriceHidden = settings?.hidePriceOnCard ?? false;
    final hasImage = product.photoUrl != null && product.photoUrl!.isNotEmpty;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isEnabled ? Colors.white : Colors.grey.shade100,
      child: InkWell(
        onTap: onTapCard,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Image ---
              _buildImage(hasImage, isEnabled, isAvailable),
              const SizedBox(width: 16),

              // --- Infos ---
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(isEnabled, context),
                    const SizedBox(height: 4),
                    _buildBadges(isEnabled, isAvailable, hasTimeRestriction,
                        isPriceHidden),
                    const SizedBox(height: 6),
                    if (isEnabled && settings != null)
                      Text(
                        "${settings!.price.toStringAsFixed(2)} €",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).primaryColor),
                      ),
                  ],
                ),
              ),

              // --- Actions ---
              Column(
                children: [
                  Switch(
                    value: isEnabled,
                    activeThumbColor: Colors.green,
                    onChanged: onToggleSwitch,
                  ),
                  if (isEnabled)
                    IconButton(
                      icon: Icon(
                          isAvailable
                              ? Icons.check_circle_outline
                              : Icons.block,
                          color: isAvailable ? Colors.green : Colors.red),
                      tooltip:
                          isAvailable ? "Marquer épuisé" : "Marquer disponible",
                      onPressed: onToggleStock,
                    ),
                  // Le bouton Composite que nous avons ajouté
                  if (isEnabled && product.isComposite && franchiseeId != null)
                    IconButton(
                      icon: const Icon(Icons.tune, color: Colors.blue),
                      tooltip: "Modifier prix ingrédients",
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => FranchiseeCompositeOverridesDialog(
                            franchiseeId: franchiseeId!,
                            franchisorId: franchisorId!,
                            product: product,
                          ),
                        );
                      },
                    ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- Petits Helpers pour alléger le build ---

  Widget _buildImage(bool hasImage, bool isEnabled, bool isAvailable) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: isEnabled
            ? (isAvailable ? Colors.orange.shade50 : Colors.red.shade50)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.network(product.photoUrl!, fit: BoxFit.cover)
          : Icon(
              product.isComposite ? Icons.restaurant_menu : Icons.fastfood,
              color: isEnabled
                  ? (isAvailable ? Colors.deepOrange : Colors.red)
                  : Colors.grey,
              size: 32,
            ),
    );
  }

  Widget _buildTitleRow(bool isEnabled, BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            product.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isEnabled ? Colors.black87 : Colors.grey.shade600,
            ),
          ),
        ),
        if (product.isComposite)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.purple.shade100)),
            child: Text("MENU",
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple.shade700)),
          ),
      ],
    );
  }

  Widget _buildBadges(bool isEnabled, bool isAvailable, bool hasTimeRestriction,
      bool isPriceHidden) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (!isEnabled) _badge("Désactivé", Colors.grey, Icons.visibility_off),
        if (isEnabled && !isAvailable)
          _badge("Épuisé", Colors.red, Icons.remove_shopping_cart),
        if (isEnabled && hasTimeRestriction)
          _badge(
              "${settings?.availableStartTime} - ${settings?.availableEndTime}",
              Colors.blue,
              Icons.schedule),
        if (isEnabled && isPriceHidden)
          _badge("Prix masqué", Colors.orange, Icons.visibility_off_outlined),
      ],
    );
  }

  Widget _badge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
