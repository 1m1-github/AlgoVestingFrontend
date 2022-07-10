// flutter run -d chrome
// flutter build web

import 'dart:typed_data';
import 'dart:convert';
import 'package:algorand_dart/algorand_dart.dart';
import 'package:flutter/material.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dio/dio.dart' as dio;

void main() {
  runApp(const MyApp());
}

Codec<String, String> stringToBase64 = utf8.fuse(base64);

const NOTE_PREFIX = 'AlgoVesting 4 ';
const MIN_ROUND = 22715559;
final String START_KEY = stringToBase64.encode('START');
final String END_KEY = stringToBase64.encode('END');
const Map<AlgorandNet, int> CREATE_DAPP_ID = {
    AlgorandNet.mainnet: -1,
    AlgorandNet.testnet: 99099422,
  };
const Map<AlgorandNet, String> CREATE_DAPP_ADDR = {
    AlgorandNet.mainnet: '',
    AlgorandNet.testnet: 'QZDPW4KE356TLAGDJGPCUCU75GIAKYFLGRX3OOOWRQVY5QZTAS23VNDQSI',
  };

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlgoVesting',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'AlgoVesting'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum bodyState { qr, empty, create, withdraw, update }

class _MyHomePageState extends State<MyHomePage> {
  AlgorandNet net = AlgorandNet.testnet;

  bodyState state = bodyState.empty;
  Widget? QR;

  SessionStatus? session;
  late List<int> assets;

  WalletConnect connector = WalletConnect(
    bridge: 'https://bridge.walletconnect.org',
    clientMeta: const PeerMeta(
      name: 'AlgoVesting',
      description: 'pro-rata coins',
      url: 'https://github.com/1m1-github/AlgoVesting',
      icons: [
        'https://firebasestorage.googleapis.com/v0/b/algovesting-1m1.appspot.com/o/AlgoVesting%20logo.png?alt=media&token=b07d9f01-56a3-4a69-9703-6e15b6713af2'
      ],
    ),
  );
  late AlgorandWalletConnectProvider provider;

  _MyHomePageState() {
    provider = AlgorandWalletConnectProvider(connector);
    // Subscribe to events
    connector.on('connect', (_session) async {
      print('connect $_session');
      // session = _session;
      QR = null;
      setState(() {
        state = bodyState.empty;
      });

      final lib = AlgorandLib.lib[net]!;
      final accInfo = await lib.getAccountByAddress(session!.accounts.first);
      assets = accInfo.assets.map((e) => e.assetId).toList();
    });
    connector.on('session_update', (_payload) => print(_payload));
    connector.on('disconnect', (_session) {
      print('disconnect $_session');
      session = null;
    });
  }

  void connect() async {
    // Create a new session
    session ??= await connector.createSession(
      chainId: 4160,
      onDisplayUri: (uri) {
        print('onDisplayUri uri=$uri');
        QR = QrImage(
          data: uri,
          version: QrVersions.auto,
          size: 320,
          gapless: false,
        );
        setState(() {
          state = bodyState.qr;
        });
        print('onDisplayUri QR=$QR');
      },
    );
  }

  Widget chooseBody() {
    switch (state) {
      case bodyState.qr:
        return QR!;
      case bodyState.empty:
        return session == null ? const Text('first connect') : const Text('choose from menu');
      case bodyState.create:
        return Create(provider, net, session!, assets);
      case bodyState.withdraw:
        return Withdraw(provider, net, session!);
      case bodyState.update:
        return const Text('TODO');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('build QR=$QR');
    return Scaffold(
      appBar: AppBar(
        title: session == null ? ElevatedButton(onPressed: connect, child: const Text('connect')) : Text(session!.accounts.first),
      ),
      bottomNavigationBar: BottomAppBar(
          child: Row(
        children: [
          ElevatedButton(
              onPressed: () {
                setState(() {
                  net = AlgorandNet.mainnet;
                });
              },
              child: Text('mainnet${net == AlgorandNet.mainnet ? ' - chosen' : ''}')),
          ElevatedButton(
              onPressed: () {
                setState(() {
                  net = AlgorandNet.testnet;
                });
              },
              child: Text('testnet${net == AlgorandNet.testnet ? ' - chosen' : ''}'))
        ],
      )),
      drawer: Drawer(
        child: ListView(
          children: [
            ListTile(
              title: const Text('create'),
              onTap: () {
                if (session != null) {
                  setState(() {
                    state = bodyState.create;
                  });
                }
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('withdraw'),
              onTap: () {
                if (session != null) {
                  setState(() {
                    state = bodyState.withdraw;
                  });
                }
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('update'),
              onTap: () {
                if (session != null) {
                  setState(() {
                    state = bodyState.update;
                  });
                }
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('logout'),
              onTap: () async {
                if (session != null) {
                  // TODO not really working well - new qr does not work
                  await connector.killSession();
                  setState(() {
                    session = null;
                    state = bodyState.empty;
                  });
                }
                Navigator.pop(context);
              },
            )
          ],
        ),
      ),
      body: Center(child: chooseBody()),
    );
  }
}

enum AlgorandNet { mainnet, testnet }

class AlgorandLib {
  static const Map<AlgorandNet, String> API_URL = {
    AlgorandNet.mainnet: AlgoExplorer.MAINNET_ALGOD_API_URL,
    AlgorandNet.testnet: AlgoExplorer.TESTNET_ALGOD_API_URL,
  };
  static const Map<AlgorandNet, String> INDEXER_URL = {
    AlgorandNet.mainnet: AlgoExplorer.MAINNET_INDEXER_API_URL,
    AlgorandNet.testnet: AlgoExplorer.TESTNET_INDEXER_API_URL,
  };
  static const Map<AlgorandNet, String> API_KEY = {
    AlgorandNet.mainnet: '',
    AlgorandNet.testnet: '',
  };

  static Algorand create(net) =>
      Algorand(algodClient: AlgodClient(apiUrl: API_URL[net]!, apiKey: API_KEY[net]!), indexerClient: IndexerClient(apiUrl: INDEXER_URL[net]!));
  static Map<AlgorandNet, Algorand> lib = {
    AlgorandNet.mainnet: create(AlgorandNet.mainnet),
    AlgorandNet.testnet: create(AlgorandNet.testnet),
  };

  static IndexerClient createIx(net) => IndexerClient(apiUrl: INDEXER_URL[net]!);
  static Map<AlgorandNet, IndexerClient> ix = {
    AlgorandNet.mainnet: createIx(AlgorandNet.mainnet),
    AlgorandNet.testnet: createIx(AlgorandNet.testnet),
  };
}

class Create extends StatefulWidget {
  Create(this.provider, this.net, this.session, this.assets, {Key? key}) : super(key: key);

  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;
  List<int> assets;

  @override
  State<Create> createState() => _CreateState(provider, net, session, assets);
}

class _CreateState extends State<Create> {
  _CreateState(this.provider, this.net, this.session, this.assets);
  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;
  List<int> assets;

  int? dAppId;
  String? dAppAddr;
  bool canCancel = false;
  bool done = false;
  late int asaId = assets.first;

  final TextEditingController _dAppIdController = TextEditingController();
  final TextEditingController _dAppAddrController = TextEditingController();
  final TextEditingController _benController = TextEditingController();
  final TextEditingController _numController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  // Future create() async {
  //   final lib = AlgorandLib.lib[net]!;
  //   final params = await lib.getSuggestedTransactionParams();

  //   Uint8List approvalProgramBytes = base64Decode(APPROVAL_TEAL);
  //   Uint8List clearStateProgramBytes = base64Decode(CLEAR_TEAL);
  //   final approvalProgram = TEALProgram(program: approvalProgramBytes);
  //   final clearStateProgram = TEALProgram(program: clearStateProgramBytes);

  //   final createTxn = await (ApplicationCreateTransactionBuilder()
  //         ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
  //         ..suggestedParams = params
  //         ..approvalProgram = approvalProgram
  //         ..clearStateProgram = clearStateProgram
  //         ..globalStateSchema = StateSchema(numUint: 3, numByteSlice: 1)
  //         ..localStateSchema = StateSchema(numUint: 0, numByteSlice: 0)
  //         ..onCompletion = OnCompletion.OPT_IN_OC)
  //       .build();

  //   final txnsBytes = Encoder.encodeMessagePack(createTxn.toMessagePack());
  //   final signedTxnsBytes = await provider.signTransaction(txnsBytes);

  //   try {
  //     final txId = await lib.sendRawTransactions(signedTxnsBytes);
  //     print('txId = $txId');

  //     final pendingTxn = await lib.waitForConfirmation(txId);

  //     print('pendingTxn=${pendingTxn}');

  //     dAppId = pendingTxn.applicationIndex;
  //     print('dAppId=${dAppId}');
  //     dAppAddr = Address.forApplication(dAppId!).encodedAddress;

  //     print('dAppAddr=${dAppAddr}');
  //     setState(() {
  //       _dAppIdController.text = dAppId.toString();
  //       _dAppAddrController.text = dAppAddr.toString();
  //     });
  //   } on AlgorandException catch (ex) {
  //     final cause = ex.cause;
  //     if (cause is dio.DioError) {
  //       print('AlgorandException ' + cause.response?.data['message']);
  //     }
  //   }
  // }

  Future create() async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    final List<RawTransaction> txns = [];

    final cancancel = canCancel ? 1 : 0;
    final end = int.parse(_endController.text);
    final amount = int.parse(_numController.text);
    final ben = _benController.text;

    // test that this works
    try {
      Address.fromAlgorandAddress(address: ben);
    } catch (e) {
      return;
    }
    if (asaId <= 0) return;
    if (amount <= 0) return;
    final now = DateTime.now();
    if (end <= now.millisecondsSinceEpoch / 1000) return;

    final algoTxn = await (PaymentTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..receiver = Address.fromAlgorandAddress(address: CREATE_DAPP_ADDR[net]!)
          ..amount = 741500
          ..suggestedParams = params)
        .build();
    txns.add(algoTxn);

    final argumentsOptIn = 'str:optin'.toApplicationArguments();
    final callOptInTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..arguments = argumentsOptIn
          ..foreignAssets = [asaId]
          ..applicationId = CREATE_DAPP_ID[net]!
          ..suggestedParams = params)
        .build();
    txns.add(callOptInTxn);

    final asaTxn = await (AssetTransferTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..receiver = Address.fromAlgorandAddress(address: CREATE_DAPP_ADDR[net]!)
          ..assetId = asaId
          ..amount = amount
          ..suggestedParams = params)
        .build();
    txns.add(asaTxn);

    final argumentsCreate = 'str:create,int:$cancancel,int:$end'.toApplicationArguments();
    final callCreateTxn = await (ApplicationCallTransactionBuilder()
          // ..note = Uint8List.fromList(utf8.encode('$NOTE_PREFIX$ben'))
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..arguments = argumentsCreate
          ..foreignAssets = [asaId]
          ..accounts = [Address.fromAlgorandAddress(address: ben)]
          ..applicationId = CREATE_DAPP_ID[net]!
          ..suggestedParams = params)
        .build();
    txns.add(callCreateTxn);

    AtomicTransfer.group(txns);
    final txnsBytes = txns.map((txn) => Encoder.encodeMessagePack(txn.toMessagePack())).toList();
    final signedTxnsBytes = await provider.signTransactions(txnsBytes);

    try {
      final txId = await lib.sendRawTransactions(signedTxnsBytes);
      print('txId = $txId');

      final pendingTxn = await lib.waitForConfirmation(txId);

      print('pendingTxn=${pendingTxn}');

      setState(() {
        done = true;
      });
    } on AlgorandException catch (ex) {
      final cause = ex.cause;
      if (cause is dio.DioError) {
        print('AlgorandException ' + cause.response?.data['message']);
      }
    }
  }

  num rate() {
    final now = DateTime.now();
    final start = now.millisecondsSinceEpoch / 1000;
    final end = int.parse(_endController.text);
    final amount = int.parse(_numController.text);
    return (end - start) / amount;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(children: [
        ElevatedButton(onPressed: create, child: Text('Step 1 - create dApp')),
        TextField(
          controller: _dAppIdController,
          decoration: InputDecoration(label: const Text('dAPP ID')),
        ),
        TextField(
          controller: _dAppAddrController,
          decoration: InputDecoration(label: const Text('dAPP Addr')),
        ),
        Checkbox(
          value: canCancel,
          onChanged: (bool? value) {
            setState(() {
              canCancel = value!;
            });
          },
        ),
        DropdownButton<int>(
          items: assets.map((int e) => DropdownMenuItem<int>(child: Text(e.toString()), value: e)).toList(),
          onChanged: (int? value) {
            asaId = value!;
          },
        ),
        TextField(
          controller: _numController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(label: const Text('Quantity')),
        ),
        TextField(
          controller: _endController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(label: const Text('END epoch timestamp')),
        ),
        Text('${rate()} [ca. - is your device time accurate?]'),
        TextField(
          controller: _benController,
          decoration: InputDecoration(label: const Text('Beneficiary')),
        ),
        ElevatedButton(onPressed: setup, child: Text('Step 2 - setup dApp')),
        done ? Text('DONE') : Container(),
      ]),
    );
  }
}

class Withdraw extends StatefulWidget {
  Withdraw(this.provider, this.net, this.session, {Key? key}) : super(key: key);

  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;

  @override
  State<Withdraw> createState() => _WithdrawState(provider, net, session);
}

class _WithdrawState extends State<Withdraw> {
  _WithdrawState(this.provider, this.net, this.session);
  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;

  bool done = false;

  List<Transaction>? txns;

  @override
  void initState() {
    super.initState();
    findTxns();
  }

  void withdraw(int dAppId) async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    final arguments = 'str:withdraw'.toApplicationArguments();
    final callTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..arguments = arguments
          ..applicationId = dAppId
          ..suggestedParams = params)
        .build();

    final txnsBytes = Encoder.encodeMessagePack(callTxn.toMessagePack());
    final signedTxnsBytes = await provider.signTransaction(txnsBytes);

    try {
      final txId = await lib.sendRawTransactions(signedTxnsBytes);
      print('txId = $txId');

      final pendingTxn = await lib.waitForConfirmation(txId);

      print('pendingTxn=${pendingTxn}');

      setState(() {
        done = true;
      });
    } on AlgorandException catch (ex) {
      final cause = ex.cause;
      if (cause is dio.DioError) {
        print('AlgorandException ' + cause.response?.data['message']);
      }
    }
  }

  void findTxns() async {
    final lib = AlgorandLib.lib[net]!;
    final searchResponse = await lib
        .indexer()
        .transactions()
        .whereTransactionType(TransactionType.APPLICATION_CALL)
        .afterMinRound(MIN_ROUND)
        .whereNotePrefix('$NOTE_PREFIX${session.accounts.first}')
        .search();
    txns = searchResponse.transactions;
    setState(() {});
    print('findTxns=${txns?.length}');
  }

  Future<String> txnTileFutureInfo(int appId, String appAddr) async {
    final lib = AlgorandLib.lib[net]!;

    final accInfoFuture = lib.getAccountByAddress(appAddr);
    final applicationSearchResponseFuture = lib.indexer().applications().whereApplicationId(appId).search(limit: 1);
    final futures = await Future.wait([accInfoFuture, applicationSearchResponseFuture]);
    final accInfo = futures[0] as AccountInformation;
    final applicationSearchResponse = futures[1] as SearchApplicationsResponse;

    final amount = accInfo.assets.first.amount;
    final assetId = accInfo.assets.first.assetId;

    final application = applicationSearchResponse.applications.first;
    int? start;
    int? end;
    num? rate;
    for (TealKeyValue kv in application.params.globalState) {
      if (kv.key == START_KEY) start = kv.value.uint;
      if (kv.key == END_KEY) end = kv.value.uint;
    }
    if (start is int && end is int) rate = (end - start) / amount;
    String rateStr = rate is num ? rate.toString() : '?';

    return 'total $amount - withdraw rate $rateStr [ASA $assetId / sec]';
  }

  Widget txnTile(Transaction t) {
    final appId = t.applicationTransaction!.applicationId;
    final appAddr = Address.forApplication(appId).encodedAddress;

    return ListTile(
      title: FutureBuilder(
        builder: ((context, snapshot) {
          return Text(snapshot.hasData ? snapshot.data as String : 'loading...');
        }),
        future: txnTileFutureInfo(appId, appAddr),
      ),
      subtitle: Text(appAddr),
      trailing: ElevatedButton(onPressed: () => withdraw(appId), child: const Text('withdraw')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        child: txns == null
            ? const Text('searching')
            : txns!.isEmpty
                ? const Text('your account is not the beneficiary of any AlgoVesting dApps')
                : ListView(
                    children: txns!.map(txnTile).toList(),
                  ));
  }
}

class Update extends StatefulWidget {
  Update(this.provider, this.net, this.session, this.assets, {Key? key}) : super(key: key);

  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;
  List<int> assets;

  @override
  State<Create> createState() => _UpdateState(provider, net, session, assets);
}

class _UpdateState extends State<Create> {
  _UpdateState(this.provider, this.net, this.session, this.assets);
  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;
  List<int> assets;

  int? dAppId;
  String? dAppAddr;
  bool canCancel = false;
  bool done = false;
  late int asaId = assets.first;

  final TextEditingController _dAppIdController = TextEditingController();
  final TextEditingController _dAppAddrController = TextEditingController();
  final TextEditingController _benController = TextEditingController();
  final TextEditingController _numController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  Future update() async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    final List<RawTransaction> txns = [];

    final end = int.parse(_endController.text);
    final amount = int.parse(_numController.text);

    // test that this works
    if (asaId <= 0) return;
    if (amount <= 0) return;
    if (end <= 0) return;

    final arguments = 'str:update,int:$end'.toApplicationArguments();
    final callTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..arguments = arguments
          ..foreignAssets = [asaId]
          ..applicationId = dAppId!
          ..suggestedParams = params)
        .build();
    txns.add(callTxn);

    final asaTxn = await (AssetTransferTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..receiver = Address.fromAlgorandAddress(address: dAppAddr!)
          ..assetId = asaId
          ..amount = amount
          ..suggestedParams = params)
        .build();
    txns.add(asaTxn);

    AtomicTransfer.group(txns);
    final txnsBytes = txns.map((txn) => Encoder.encodeMessagePack(txn.toMessagePack())).toList();
    final signedTxnsBytes = await provider.signTransactions(txnsBytes);

    try {
      final txId = await lib.sendRawTransactions(signedTxnsBytes);
      print('txId = $txId');

      final pendingTxn = await lib.waitForConfirmation(txId);

      print('pendingTxn=${pendingTxn}');

      setState(() {
        done = true;
      });
    } on AlgorandException catch (ex) {
      final cause = ex.cause;
      if (cause is dio.DioError) {
        print('AlgorandException ' + cause.response?.data['message']);
      }
    }
  }

  num rate() {
    final now = DateTime.now();
    final start = now.millisecondsSinceEpoch / 1000;
    final end = int.parse(_endController.text);
    final amount = int.parse(_numController.text);
    return (end - start) / amount;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(children: [
        ElevatedButton(onPressed: create, child: Text('Step 1 - create dApp')),
        TextField(
          controller: _dAppIdController,
          decoration: InputDecoration(label: const Text('dAPP ID')),
        ),
        TextField(
          controller: _dAppAddrController,
          decoration: InputDecoration(label: const Text('dAPP Addr')),
        ),
        Checkbox(
          value: canCancel,
          onChanged: (bool? value) {
            setState(() {
              canCancel = value!;
            });
          },
        ),
        DropdownButton<int>(
          items: assets.map((int e) => DropdownMenuItem<int>(child: Text(e.toString()), value: e)).toList(),
          onChanged: (int? value) {
            asaId = value!;
          },
        ),
        TextField(
          controller: _numController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(label: const Text('Quantity')),
        ),
        TextField(
          controller: _endController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(label: const Text('END epoch timestamp')),
        ),
        Text('${rate()} [ca. - is your device time accurate?]'),
        TextField(
          controller: _benController,
          decoration: InputDecoration(label: const Text('Beneficiary')),
        ),
        ElevatedButton(onPressed: setup, child: Text('Step 2 - setup dApp')),
        done ? Text('DONE') : Container(),
      ]),
    );
  }
}