import 'package:arp_scout/data/repositories/arp_repository.dart';
import 'package:arp_scout/domain/models/network_adapter_info.dart';
import 'package:arp_scout/ui/features/scout/view_models/arp_scout_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

class _FakeArpRepository extends ArpRepository {
  @override
  Future<List<NetworkAdapterInfo>> getAvailableAdapters() async {
    return const [
      NetworkAdapterInfo(
        name: 'eth0',
        ipAddress: '192.168.1.150',
        subnetCidr: '192.168.1.0/24',
      ),
      NetworkAdapterInfo(
        name: 'wlan0',
        ipAddress: '10.0.0.45',
        subnetCidr: '10.0.0.0/24',
      ),
      NetworkAdapterInfo(
        name: 'docker0',
        ipAddress: '172.17.0.1',
        subnetCidr: '172.17.0.0/16',
      ),
      NetworkAdapterInfo.all,
    ];
  }
}

void main() {
  group('ArpScoutViewModel Adapter Matching & Inter-App Tests', () {
    late _FakeArpRepository repository;
    late ArpScoutViewModel viewModel;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      repository = _FakeArpRepository();
      viewModel = ArpScoutViewModel(repository: repository);
      // Wait for async _init to populate adapters
      await Future.delayed(const Duration(milliseconds: 20));
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('selectMatchingAdapter matches exact physical interface by IP address (Primary Match)', () {
      expect(viewModel.adapters.length, equals(4));

      viewModel.selectMatchingAdapter(adapterIp: '10.0.0.45');
      expect(viewModel.selectedAdapter.name, equals('wlan0'));
      expect(viewModel.selectedAdapter.ipAddress, equals('10.0.0.45'));
      expect(viewModel.scanProgress.targetSubnet, equals('10.0.0.0/24'));
    });

    test('selectMatchingAdapter falls back to interface name match (Secondary Match)', () {
      viewModel.selectMatchingAdapter(adapterName: 'docker0');
      expect(viewModel.selectedAdapter.name, equals('docker0'));
      expect(viewModel.selectedAdapter.ipAddress, equals('172.17.0.1'));
      expect(viewModel.scanProgress.targetSubnet, equals('172.17.0.0/16'));
    });

    test('selectMatchingAdapter prioritizes IP address over interface name when both supplied', () {
      // Pass adapterIp of eth0 and adapterName of wlan0
      viewModel.selectMatchingAdapter(
        adapterIp: '192.168.1.150',
        adapterName: 'wlan0',
      );
      expect(viewModel.selectedAdapter.name, equals('eth0'));
      expect(viewModel.selectedAdapter.ipAddress, equals('192.168.1.150'));
    });

    test('selectMatchingAdapter leaves current selection intact when neither IP nor name matches', () {
      viewModel.selectMatchingAdapter(adapterIp: '10.0.0.45');
      expect(viewModel.selectedAdapter.name, equals('wlan0'));

      viewModel.selectMatchingAdapter(
        adapterIp: '99.99.99.99',
        adapterName: 'nonexistent_interface',
      );
      expect(viewModel.selectedAdapter.name, equals('wlan0'));
    });

    test('handleIncomingCommand updates adapter, target subnet, and executes autoStart', () async {
      await viewModel.handleIncomingCommand(
        subnet: '10.0.0.0/24',
        adapterIp: '10.0.0.45',
        adapterName: 'wlan0',
        autoStart: false,
      );

      expect(viewModel.selectedAdapter.ipAddress, equals('10.0.0.45'));
      expect(viewModel.scanProgress.targetSubnet, equals('10.0.0.0/24'));
      expect(viewModel.scanProgress.generatedCommand, contains('10.0.0.0/24'));
    });

    test('cold start constructor pre-selects adapter and subnet', () async {
      final coldVm = ArpScoutViewModel(
        repository: repository,
        initialSubnet: '172.17.0.0/16',
        initialAdapterIp: '172.17.0.1',
        initialAdapterName: 'docker0',
        autoStart: false,
      );

      await Future.delayed(const Duration(milliseconds: 20));

      expect(coldVm.selectedAdapter.ipAddress, equals('172.17.0.1'));
      expect(coldVm.scanProgress.targetSubnet, equals('172.17.0.0/16'));
      coldVm.dispose();
    });
  });
}
