// flutter run -d chrome
// flutter build web

import 'dart:typed_data';
import 'dart:convert';
import 'package:algorand_dart/algorand_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dio/dio.dart' as dio;

void main() {
  runApp(const MyApp());
}

const NOTE_PREFIX = 'AlgoVestin'; // notes have to have length / by 4

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlgoVesting',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'AlgoVesting'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

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
      name: 'WalletConnect',
      description: 'WalletConnect Developer App',
      url: 'https://walletconnect.org',
      icons: ['https://gblobscdn.gitbook.com/spaces%2F-LJJeCjcLrr53DcT1Ml7%2Favatar.png?alt=media'],
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
              onTap: () {
                if (session != null) {
                  setState(() {
                    connector.close();
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

  Future create() async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    Uint8List approvalProgramBytes = base64Decode(
        'BSAFAQAEAqCNBiYFBVNUQVJUCUNBTkNBTkNFTANFTkQLQkVORUZJQ0lBUlkGQVNBX0lEMRkjEkAAIDEZIhJAASMxGSUSQAEZMRkkEkABAjEZgQUSQAEKQgENNhoAgARpbml0EkAAIzYaAIAId2l0aGRyYXcSQACFNhoAgAZ1cGRhdGUSQADHQgDdIyllQADXSDEAMgkSRDEWIhIyBIEDEhBEJTgQJBIlOBE2MAASEEQ2GgIXMgcNQQCtKTYaARdnKDIHZyo2GgIXZys2HAFngA5PUklHX05VTV9DT0lOUzMBEmcnBDYwAGexJLIQMgqyFDYwALIRI7ISs0IAbDIEIhJEK2Q1AChkNQoqZDULJwRkNQwxADQAEkQyBzQKCSEECzQLNAoJCjIKNAxwAEEANwshBAo1AbEkshA0ALIUNAyyETQBshKzKDIHZ0IAG0IAFjIEIhIyCTEAEhBAAAtCAAZCAANCAAIjQyJD');
    Uint8List clearStateProgramBytes = base64Decode('BYEB');
    final approvalProgram = TEALProgram(program: approvalProgramBytes);
    final clearStateProgram = TEALProgram(program: clearStateProgramBytes);

    final createTxn = await (ApplicationCreateTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..suggestedParams = params
          ..approvalProgram = approvalProgram
          ..clearStateProgram = clearStateProgram
          ..globalStateSchema = StateSchema(numUint: 5, numByteSlice: 1)
          ..localStateSchema = StateSchema(numUint: 0, numByteSlice: 0)
          ..onCompletion = OnCompletion.OPT_IN_OC)
        .build();

    final txnsBytes = Encoder.encodeMessagePack(createTxn.toMessagePack());
    final signedTxnsBytes = await provider.signTransaction(txnsBytes);

    try {
      final txId = await lib.sendRawTransactions(signedTxnsBytes);
      print('txId = $txId');

      final pendingTxn = await lib.waitForConfirmation(txId);

      print('pendingTxn=${pendingTxn}');

      dAppId = pendingTxn.applicationIndex;
      print('dAppId=${dAppId}');
      dAppAddr = Address.forApplication(dAppId!).encodedAddress;
      print('dAppAddr=${dAppAddr}');
      setState(() {
        _dAppIdController.text = dAppId.toString();
        _dAppAddrController.text = dAppAddr.toString();
      });
    } on AlgorandException catch (ex) {
      final cause = ex.cause;
      if (cause is dio.DioError) {
        print('AlgorandException ' + cause.response?.data['message']);
      }
    }
  }

  Future setup() async {
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
    if (end <= 0) return;

    final algoTxn = await (PaymentTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..receiver = Address.fromAlgorandAddress(address: dAppAddr!)
          ..amount = 201000
          ..suggestedParams = params)
        .build();
    txns.add(algoTxn);

    final arguments = 'str:init,int:$cancancel,int:$end'.toApplicationArguments();
    final callTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: session.accounts.first)
          ..arguments = arguments
          ..foreignAssets = [asaId]
          ..accounts = [Address.fromAlgorandAddress(address: ben)]
          ..applicationId = dAppId!
          ..suggestedParams = params)
        .build();
    txns.add(callTxn);

    final asaTxn = await (AssetTransferTransactionBuilder()
          ..note = Uint8List.fromList(utf8.encode('$NOTE_PREFIX$ben'))
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

  List<Transaction>? txns;

  @override
  void initState() {
    super.initState();
    findTxns();
  }

  void findTxns() async {
    final lib = AlgorandLib.lib[net]!;
    final searchResponse = await lib.indexer().transactions().afterMinRound(22715559).whereNotePrefix('$NOTE_PREFIX${session.accounts.first}').search();
    txns = searchResponse.transactions;
    print('findTxns=${txns?.length}');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        child: txns == null
            ? Text('searching')
            : ListView(
                children: txns!
                    .map((t) => ListTile(
                          title: Text(t.assetTransferTransaction!.receiver),
                        ))
                    .toList(),
              ));
  }
}
