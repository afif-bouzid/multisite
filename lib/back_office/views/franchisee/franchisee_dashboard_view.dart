import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '../../../core/providers/update_provider.dart';
class FranchiseeDashboardView extends StatelessWidget {
  final Widget child;
  const FranchiseeDashboardView({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    const Color bgSidebar = Color(0xFF121212); 
    const Color activeAccent = Color(0xFFD4AF37); 
    const Color inactiveIcon =
        Color(0xFF666666); 
    return Scaffold(
      backgroundColor: bgSidebar,
      body: Row(
        children: [
          SizedBox(
            width: 120, 
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    const SizedBox(height: 40),
                    _BrandAvatar(),
                    const SizedBox(height: 60), 
                    _PremiumNavIcon(
                      icon: Icons.point_of_sale,
                      label: "Caisse",
                      route: '/franchisee_dashboard',
                      activeColor: activeAccent,
                      inactiveColor: inactiveIcon,
                    ),
                    const SizedBox(height: 30),
                    _PremiumNavIcon(
                      icon: Icons.leaderboard_outlined,
                      label: "Stats",
                      route: '/franchisee_stats',
                      activeColor: Colors.white,
                      inactiveColor: inactiveIcon,
                    ),
                    const SizedBox(height: 30),
                    const _KioskSwitchButton(),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    children: [
                      Consumer<UpdateProvider>(
                        builder: (_, update, __) {
                          if (!update.hasUpdate) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.redAccent, blurRadius: 6)
                                ]),
                          );
                        },
                      ),
                      _MenuTriggerButton(activeColor: activeAccent),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7), 
                borderRadius: BorderRadius.circular(32), 
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(-10, 0),
                  )
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
class _BrandAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).franchiseUser;
    final initial = (user?.companyName ?? "O").substring(0, 1).toUpperCase();
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.1), Colors.transparent],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w300,
          fontSize: 32, 
          fontFamily: 'Times',
        ),
      ),
    );
  }
}
class _PremiumNavIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final String route;
  final Color activeColor;
  final Color inactiveColor;
  const _PremiumNavIcon({
    required this.icon,
    required this.label,
    required this.route,
    required this.activeColor,
    required this.inactiveColor,
  });
  @override
  Widget build(BuildContext context) {
    final String currentPath = GoRouterState.of(context).uri.path;
    final bool isActive = currentPath == route;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(route),
        borderRadius: BorderRadius.circular(24),
        splashColor: activeColor.withOpacity(0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color:
                isActive ? activeColor.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(24), 
            border: isActive
                ? Border.all(color: activeColor.withOpacity(0.5), width: 1.5)
                : Border.all(color: Colors.transparent),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? activeColor : inactiveColor,
                size: 36, 
              ),
              const SizedBox(height: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                    color: isActive ? activeColor : inactiveColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2),
              )
            ],
          ),
        ),
      ),
    );
  }
}
class _MenuTriggerButton extends StatelessWidget {
  final Color activeColor;
  const _MenuTriggerButton({required this.activeColor});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showAdminMenu(context),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 70, 
          height: 70,
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 15,
                offset: const Offset(0, 5),
              )
            ],
          ),
          child: const Icon(Icons.apps, color: Colors.white, size: 34),
        ),
      ),
    );
  }
  void _showAdminMenu(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Fermer",
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return _AdminMenuOverlay(parentContext: context);
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 20 * anim1.value, sigmaY: 20 * anim1.value),
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: FadeTransition(opacity: anim1, child: child),
          ),
        );
      },
    );
  }
}
class _AdminMenuOverlay extends StatelessWidget {
  final BuildContext parentContext;
  const _AdminMenuOverlay({required this.parentContext});
  @override
  Widget build(BuildContext context) {
    final authProvider =
        Provider.of<AuthProvider>(parentContext, listen: false);
    final user = authProvider.franchiseUser;
    final isBoss = user?.role == 'franchisee';
    final modules = user?.enabledModules ?? {};
    return Center(
      child: Container(
        width: 800, 
        padding: const EdgeInsets.all(48), 
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 100,
              spreadRadius: 20,
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Menu Gestion",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w300)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text((user?.companyName ?? "").toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFFD4AF37),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5)),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 40),
                )
              ],
            ),
            const SizedBox(height: 50),
            Wrap(
              spacing: 24,
              runSpacing: 24,
              children: [
                if (isBoss) ...[
                  _AdminTile(
                    icon: Icons.edit_calendar,
                    label: "Produits",
                    color: Colors.blueAccent,
                    onTap: () => _nav(context, '/franchisee_catalogue'),
                  ),
                  _AdminTile(
                    icon: Icons.people,
                    label: "Équipe",
                    color: Colors.purpleAccent,
                    onTap: () => _nav(context, '/franchisee_team'),
                  ),
                  if (modules['kiosk'] == true)
                    _AdminTile(
                      icon: Icons.touch_app,
                      label: "Borne",
                      color: Colors.tealAccent,
                      onTap: () => _nav(context, '/franchisee_kiosk_config'),
                    ),
                  if (modules['deals'] == true)
                    _AdminTile(
                      icon: Icons.local_offer,
                      label: "Offres",
                      color: Colors.orangeAccent,
                      onTap: () => _nav(context, '/franchisee_deals'),
                    ),
                  _AdminTile(
                    icon: Icons.settings,
                    label: "Réglages",
                    color: Colors.grey,
                    onTap: () => _nav(context, '/franchisee_settings'),
                  ),
                ],
                _AdminTile(
                  icon: Icons.info_outline,
                  label: "À propos",
                  color: Colors.white70,
                  onTap: () => _nav(context, '/franchisee_about'),
                ),
                _AdminTile(
                  icon: Icons.logout,
                  label: "Sortir",
                  color: Colors.redAccent,
                  onTap: () {
                    authProvider.signOut();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  void _nav(BuildContext context, String route) {
    Navigator.pop(context);
    GoRouter.of(parentContext).go(route);
  }
}
class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AdminTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        hoverColor: color.withOpacity(0.2),
        splashColor: color.withOpacity(0.4),
        child: Container(
          width: 160,
          height: 160,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(32)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50, color: color), 
              const SizedBox(height: 20),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 18 
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _KioskSwitchButton extends StatelessWidget {
  const _KioskSwitchButton();
  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthProvider>(context).franchiseUser;
    if (user == null) return const SizedBox.shrink();
    final String targetStoreId = user.effectiveStoreId;
    final bool hasKioskOption = user.enabledModules['kiosk'] ?? false;
    if (!hasKioskOption) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sessions')
          .where('franchiseeId', isEqualTo: targetStoreId)
          .where('isClosed', isEqualTo: false)
          .limit(1)
          .snapshots(),
      builder: (context, sessionSnapshot) {
        if (!sessionSnapshot.hasData || sessionSnapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(targetStoreId)
              .snapshots(),
          builder: (context, userSnapshot) {
            bool isActive = false;
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final data = userSnapshot.data!.data() as Map<String, dynamic>;
              isActive = data['isKioskActive'] ?? false;
            }
            final color =
                isActive ? const Color(0xFF27AE60) : const Color(0xFFC0392B);
            final icon =
                isActive ? Icons.desktop_mac : Icons.desktop_access_disabled;
            final label = isActive ? "Borne ON" : "Borne OFF";
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(targetStoreId)
                      .set({'isKioskActive': !isActive},
                          SetOptions(merge: true));
                },
                borderRadius: BorderRadius.circular(24),
                splashColor: color.withOpacity(0.2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: color.withOpacity(0.5), width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: color, size: 30),
                      const SizedBox(height: 6),
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
