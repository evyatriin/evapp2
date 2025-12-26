import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import 'charging_service.dart';
import '../community/check_in_sheet.dart';
import '../authentication/user_provider.dart';

class ChargeScreen extends ConsumerStatefulWidget {
  const ChargeScreen({super.key});

  @override
  ConsumerState<ChargeScreen> createState() => _ChargeScreenState();
}

class _ChargeScreenState extends ConsumerState<ChargeScreen> with SingleTickerProviderStateMixin {
  final _chargingService = ChargingService();
  List<dynamic> _checkIns = [];
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final user = ref.read(userProvider);
      if (user == null) {
        setState(() {
          _isLoading = false;
          _error = "User not logged in";
        });
        return;
      }

      final checkIns = await _chargingService.getCheckIns(user.id);
      if (mounted) {
        setState(() {
          _checkIns = checkIns;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final workingCheckIns = _checkIns.where((c) => c['status'] == 'Working').toList();
    final issueCheckIns = _checkIns.where((c) => c['status'] != 'Working').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Charging History'),
        toolbarHeight: 48,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: const [
              Tab(text: 'Charged Successfully', height: 36),
              Tab(text: 'Issue with Charger', height: 36),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: _buildList(workingCheckIns, theme, true),
                    ),
                    RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: _buildList(issueCheckIns, theme, false),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (context) => const CheckInSheet(),
          ).then((_) => _loadHistory()); // Refresh after check-in
        },
        icon: Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.duotone)),
        label: const Text('Check-In'),
      ),
    );
  }

  Widget _buildList(List<dynamic> items, ThemeData theme, bool isSuccess) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSuccess ? PhosphorIcons.lightning(PhosphorIconsStyle.duotone) : PhosphorIcons.warning(PhosphorIconsStyle.duotone),
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isSuccess ? 'No successful charges yet' : 'No issues reported',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final createdAt = DateTime.parse(item['created_at']);
        final status = item['status'];
        final rating = item['rating'];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSuccess ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              child: Icon(
                isSuccess ? PhosphorIcons.check(PhosphorIconsStyle.bold) : PhosphorIcons.warning(PhosphorIconsStyle.bold),
                color: isSuccess ? Colors.green : Colors.red,
              ),
            ),
            title: Text(DateFormat.yMMMd().add_jm().format(createdAt)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status: $status'),
                if (item['comment'] != null && item['comment'].toString().isNotEmpty)
                  Text('"${item['comment']}"', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ),
            trailing: rating != null
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(rating.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Icon(Icons.star, size: 16, color: Colors.amber),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}
