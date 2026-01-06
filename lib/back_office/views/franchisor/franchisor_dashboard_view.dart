import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/auth_provider.dart';
import '../../../core/repository/repository.dart';
import 'franchisor_catalogue_view.dart';
import 'franchisor_filters_view.dart';
import 'franchisor_franchisees_view.dart';
import 'franchisor_groups_view.dart';
import 'franchisor_kiosk_view.dart' hide CategoryEditorDialog;
import 'franchisor_sections_view.dart';

class FranchisorDashboardView extends StatefulWidget {
  const FranchisorDashboardView({super.key});

  @override
  State<FranchisorDashboardView> createState() => _FranchisorDashboardViewState();
}

class _FranchisorDashboardViewState extends State<FranchisorDashboardView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final Color _bgGradientStart = const Color(0xFF1c2e4a);
  final Color _bgGradientEnd = const Color(0xFF000000);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToFranchisees(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: Scaffold(
            appBar: AppBar(
              title: const Text("GESTION DU RÉSEAU"),
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_bgGradientStart, _bgGradientEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              centerTitle: true,
              toolbarHeight: 70,
            ),
            body: const FranchiseesView(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final userEmail = authProvider.firebaseUser?.email ?? "Non connecté";

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)),
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(170),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_bgGradientStart, _bgGradientEnd],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 15.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24, width: 1),
                            ),
                            child: const CircleAvatar(
                              backgroundColor: Colors.white10,
                              radius: 22,
                              child: Icon(Icons.admin_panel_settings_rounded, color: Colors.amber, size: 24),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "PORTAIL FRANCHISEUR",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              Text(
                                  userEmail,
                                  style: TextStyle(color: Colors.grey[400], fontSize: 11)
                              ),
                            ],
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => _navigateToFranchisees(context),
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.orange.shade800, Colors.orange.shade500],
                                  begin: Alignment.bottomLeft,
                                  end: Alignment.topRight,
                                ),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 1,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.store_mall_directory_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    "Réseau",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          IconButton(
                            icon: const Icon(Icons.power_settings_new_rounded, color: Colors.white54, size: 28),
                            onPressed: () async => await authProvider.signOut(),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 80,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        indicator: const UnderlineTabIndicator(borderSide: BorderSide.none),
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        onTap: (index) => setState((){}),
                        tabs: [
                          _buildSharpTab(0, "Produits", Icons.fastfood_rounded, const Color(0xFFFF416C), const Color(0xFFFF4B2B)),
                          _buildSharpTab(1, "Catégories", Icons.category_rounded, const Color(0xFF00B4DB), const Color(0xFF0083B0)),
                          _buildSharpTab(2, "Gr. Sections", Icons.list, const Color(0xFF56ab2f), const Color(0xFFa8e063)),
                          _buildSharpTab(3, "Groupes", Icons.list_alt, const Color(0xFF8E2DE2), const Color(0xFF4A00E0)),
                          _buildSharpTab(4, "Filtres", Icons.tune_rounded, const Color(0xFFF7971E), const Color(0xFFFFD200)),
                          _buildSharpTab(5, "Borne", Icons.phonelink_setup_rounded, const Color(0xFF232526), const Color(0xFF414345)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              _KeepAlivePage(child: CatalogueView()),
              _KeepAlivePage(child: KioskView()),
              _KeepAlivePage(child: SectionsView()),
              _KeepAlivePage(child: SectionGroupsView()),
              _KeepAlivePage(child: FiltersView()),
              _KeepAlivePage(child: FranchisorGlobalConfigView()),
            ],
          ),
          floatingActionButton: _tabController.index == 5
              ? SizedBox(
            height: 70,
            width: 190,
            child: FloatingActionButton.extended(
              elevation: 0,
              highlightElevation: 0,
              icon: const Icon(Icons.add_photo_alternate_rounded, color: Colors.white, size: 28),
              label: const Text("Ajouter Fond", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              backgroundColor: const Color(0xFF232526),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
              onPressed: () => _showAddWallpaperDialog(context),
            ),
          )
              : null,
        ),
      ),
    );
  }

  Widget _buildSharpTab(int index, String label, IconData icon, Color cStart, Color cEnd) {
    final bool isSelected = _tabController.index == index;

    return Tab(
      height: 60,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [cStart, cEnd], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: isSelected
              ? null
              : Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white60,
                size: 24
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddWallpaperDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final ImagePicker picker = ImagePicker();
    XFile? pickedFile;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)),
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.wallpaper, color: Colors.blueGrey[800], size: 30),
                  const SizedBox(width: 15),
                  const Text("Nouveau Thème"),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: "Nom du thème",
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 25),
                  InkWell(
                    onTap: () async {
                      final XFile? image = await picker.pickImage(
                          source: ImageSource.gallery, imageQuality: 85);
                      if (image != null) {
                        setStateDialog(() => pickedFile = image);
                      }
                    },
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: pickedFile == null ? Colors.grey[200] : null,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                          image: pickedFile != null
                              ? DecorationImage(image: FileImage(File(pickedFile!.path)), fit: BoxFit.cover)
                              : null
                      ),
                      child: pickedFile == null
                          ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.add_a_photo_rounded, color: Colors.grey, size: 50),
                          SizedBox(height: 10),
                          Text("Choisir image", style: TextStyle(color: Colors.grey)),
                        ],
                      )
                          : null,
                    ),
                  ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 20.0),
                      child: LinearProgressIndicator(),
                    )
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Annuler", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: (pickedFile == null || isLoading) ? null : () async {
                    setStateDialog(() => isLoading = true);
                    try {
                      final repo = FranchiseRepository();
                      final auth = Provider.of<AuthProvider>(context, listen: false);

                      String path = 'wallpapers/${DateTime.now().millisecondsSinceEpoch}.jpg';
                      String url = await repo.uploadUniversalFile(pickedFile!, path);

                      await FirebaseFirestore.instance.collection('kiosk_medias').add({
                        'franchisorId': auth.firebaseUser!.uid,
                        'name': nameController.text.isEmpty ? 'Sans nom' : nameController.text,
                        'type': 'image',
                        'url': url,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      if (mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Succès !")));
                      }
                    } catch (e) {
                      setStateDialog(() => isLoading = false);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
                    }
                  },
                  child: const Text("Enregistrer"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class FranchisorGlobalConfigView extends StatefulWidget {
  const FranchisorGlobalConfigView({super.key});

  @override
  State<FranchisorGlobalConfigView> createState() => _FranchisorGlobalConfigViewState();
}

class _FranchisorGlobalConfigViewState extends State<FranchisorGlobalConfigView> {
  bool _isUpdating = false;

  Future<void> _updateTechnicalButton(String typeKey, String currentOtherUrl) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image == null) return;
    setState(() => _isUpdating = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final repo = FranchiseRepository();
      String path = 'buttons/${auth.firebaseUser!.uid}_$typeKey.jpg';
      String url = await repo.uploadUniversalFile(image, path);
      if (typeKey == 'dineIn') {
        await repo.updateGlobalButtonImages(auth.firebaseUser!.uid, url, currentOtherUrl);
      } else {
        await repo.updateGlobalButtonImages(auth.firebaseUser!.uid, currentOtherUrl, url);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  Future<void> _deleteTechnicalButton(String typeKey) async {
    setState(() => _isUpdating = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final repo = FranchiseRepository();
      await repo.deleteGlobalButtonImage(auth.firebaseUser!.uid, typeKey);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  Future<void> _deleteMedia(String docId) async {
    bool? confirm = await showDialog(
        context: context,
        builder: (ctx) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: AlertDialog(
              title: const Text("Supprimer l'image ?"),
              actions: [
                TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text("Annuler")),
                TextButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text("Supprimer", style: TextStyle(color: Colors.red))),
              ]
          ),
        )
    );
    if(confirm == true) {
      await FirebaseFirestore.instance.collection('kiosk_medias').doc(docId).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.franchiseUser;
    if (user == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          String? liveDineInUrl;
          String? liveTakeawayUrl;
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>;
            liveDineInUrl = data['dineInImageUrl'];
            liveTakeawayUrl = data['takeawayImageUrl'];
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                    side: BorderSide(color: Colors.grey.shade200)
                ),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.blueGrey.shade50, shape: BoxShape.circle),
                              child: const Icon(Icons.touch_app_rounded, color: Colors.blueGrey, size: 28)
                          ),
                          const SizedBox(width: 15),
                          const Text("ACCUEIL BORNE", style: TextStyle(fontWeight: FontWeight.w800, color: Colors.blueGrey)),
                        ],
                      ),
                      const SizedBox(height: 35),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildInteractiveBtn(
                            label: "SUR PLACE",
                            icon: Icons.restaurant_rounded,
                            url: liveDineInUrl,
                            color: Colors.orange.shade50,
                            accentColor: Colors.orange,
                            onTap: () => _updateTechnicalButton('dineIn', liveTakeawayUrl ?? ''),
                            onDelete: () => _deleteTechnicalButton('dineIn'),
                          ),
                          _buildInteractiveBtn(
                            label: "À EMPORTER",
                            icon: Icons.shopping_bag_rounded,
                            url: liveTakeawayUrl,
                            color: Colors.brown.shade50,
                            accentColor: Colors.brown,
                            onTap: () => _updateTechnicalButton('takeaway', liveDineInUrl ?? ''),
                            onDelete: () => _deleteTechnicalButton('takeaway'),
                          ),
                        ],
                      ),
                      if (_isUpdating) const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Row(
                children: const [
                  Icon(Icons.photo_library_rounded, color: Colors.black87, size: 28),
                  SizedBox(width: 12),
                  Text("Fonds d'écran actifs", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 600,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('kiosk_medias')
                      .where('franchisorId', isEqualTo: auth.firebaseUser!.uid)
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, mediaSnapshot) {
                    if (!mediaSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = mediaSnapshot.data!.docs;
                    if (docs.isEmpty) return const Center(child: Text("Aucun fond d'écran"));

                    return GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, crossAxisSpacing: 20, mainAxisSpacing: 20, childAspectRatio: 1.5),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: CachedNetworkImage(
                                    imageUrl: data['url'], fit: BoxFit.cover,
                                    placeholder: (c, u) => Container(color: Colors.grey[200]),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 10, right: 10,
                              child: InkWell(
                                onTap: () => _deleteMedia(docs[index].id),
                                child: CircleAvatar(
                                  backgroundColor: Colors.white,
                                  radius: 18,
                                  child: const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
                                ),
                              ),
                            )
                          ],
                        );
                      },
                    );
                  },
                ),
              )
            ],
          );
        });
  }

  Widget _buildInteractiveBtn({
    required String label,
    required IconData icon,
    required String? url,
    required Color color,
    required Color accentColor,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 140,
            width: 140,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: url != null ? Colors.transparent : accentColor.withOpacity(0.3), width: 2),
              image: url != null
                  ? DecorationImage(image: CachedNetworkImageProvider(url), fit: BoxFit.cover)
                  : null,
            ),
            child: url == null
                ? Icon(icon, size: 50, color: accentColor.withOpacity(0.5))
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: accentColor)),
        if(url != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: onDelete,
              child: Text("Supprimer", style: TextStyle(color: Colors.red[300], fontSize: 13, decoration: TextDecoration.underline)),
            ),
          )
      ],
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
  @override
  bool get wantKeepAlive => true;
}