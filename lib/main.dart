// flutter build web && firebase deploy
// flutter run -d chrome
// flutter build web
// firebase deploy
// firebase login

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' as convert;
import 'package:algorand_dart/algorand_dart.dart';
import 'package:flutter/material.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dio/dio.dart' as dio;

void main() {
  runApp(const MyApp());
}

convert.Codec<String, String> stringToBase64 = convert.utf8.fuse(convert.base64);

const VERSION = 4;
const NOTE_PREFIX_FOR = 'AlgoVesting$VERSION 4 ';
const NOTE_PREFIX_BY = 'AlgoVesting$VERSION by ';
const MIN_ROUND = 22715559;
final String START_KEY = stringToBase64.encode('START');
final String END_KEY = stringToBase64.encode('END');
final String CANCANCEL_KEY = stringToBase64.encode('CANCANCEL');
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

enum bodyState { qr, empty, create, withdraw, update, cancel }

class _MyHomePageState extends State<MyHomePage> {
  AlgorandNet net = AlgorandNet.testnet;

  bodyState state = bodyState.empty; // DEBUG - def=empty
  Widget? QR;

  SessionStatus? session; // = SessionStatus(chainId: 0, accounts: ['2I2IXTP67KSNJ5FQXHUJP5WZBX2JTFYEBVTBYFF3UUJ3SQKXSZ3QHZNNPY']); // DEBUG
  late List<int> assets;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<String> getWCBridge() async {
    final r = await http.get(Uri.parse('https://wc.perawallet.app/servers.json'));
    final jsonResponse = convert.jsonDecode(r.body) as Map<String, dynamic>;
    final bridges = jsonResponse["servers"];
    final rng = Random();
    final ix = rng.nextInt(bridges.length);
    return bridges[ix];
  }

  late WalletConnect connector;
  //  = WalletConnect(
  //   // bridge: 'https://bridge.walletconnect.org',
  //   bridge: 'https://wallet-connect-a.perawallet.app',
  //   // bridge: bridge,
  //   clientMeta: const PeerMeta(
  //     name: 'AlgoVesting',
  //     description: 'pro-rata coins',
  //     url: 'https://github.com/1m1-github/AlgoVesting',
  //     icons: [
  //       'https://firebasestorage.googleapis.com/v0/b/algovesting-1m1.appspot.com/o/AlgoVesting%20logo.png?alt=media&token=b07d9f01-56a3-4a69-9703-6e15b6713af2'
  //     ],
  //   ),
  // ); // DEBUG
  late AlgorandWalletConnectProvider provider; // = AlgorandWalletConnectProvider(connector); // DEBUG

  Future init() async {
    final bridge = await getWCBridge();
    connector = WalletConnect(
      // bridge: 'https://bridge.walletconnect.org',
      // bridge: 'https://wallet-connect-a.perawallet.app',
      bridge: bridge,
      clientMeta: const PeerMeta(
        name: 'AlgoVesting',
        description: 'pro-rata coins',
        url: 'https://github.com/1m1-github/AlgoVesting',
        icons: [
          'https://firebasestorage.googleapis.com/v0/b/algovesting-1m1.appspot.com/o/AlgoVesting%20logo.png?alt=media&token=b07d9f01-56a3-4a69-9703-6e15b6713af2'
        ],
      ),
    );

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
        return session == null ? ElevatedButton(onPressed: connect, child: Text('connect')) : const Text('choose from menu');
      case bodyState.create:
        // return Create(provider, net, session!, [92125658, 92125659]); // DEBUG
        return Create(provider, net, session!, assets);
      case bodyState.withdraw:
        return Withdraw(provider, net, session!);
      case bodyState.update:
        // return UnderConstruction();
        return Update(provider, net, session!);
      case bodyState.cancel:
        return UnderConstruction();
        ;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = ElevatedButton.styleFrom(primary: Colors.amber);
    print('build QR=$QR');
    return Scaffold(
      appBar: AppBar(
        title: Text('AlgoVesting'),
      ),
      bottomNavigationBar: BottomAppBar(
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, mainAxisSize: MainAxisSize.min, children: [
        Text(session == null ? '' : session!.accounts.first),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton(style: style, onPressed: null, child: Text('mainnet (not yet)${net == AlgorandNet.mainnet ? ' - chosen' : ''}')),
            ElevatedButton(
                style: style,
                onPressed: () {
                  setState(() {
                    net = AlgorandNet.testnet;
                  });
                },
                child: Text('testnet${net == AlgorandNet.testnet ? ' - chosen' : ''}'))
          ],
        )
      ])),
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
              title: const Text('update ~ UnderConstruction'),
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
              title: const Text('cancel ~ UnderConstruction'),
              onTap: () {
                if (session != null) {
                  setState(() {
                    state = bodyState.cancel;
                  });
                }
                Navigator.pop(context);
              },
            ),
            // ListTile(
            //   title: const Text('logout'),
            //   onTap: () async {
            //     if (session != null) {
            //       // TODO not really working well - new qr does not work
            //       await connector.killSession();
            //       setState(() {
            //         session = null;
            //         state = bodyState.empty;
            //       });
            //     }
            //     Navigator.pop(context);
            //   },
            // )
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

  Future create(String beneficiary, int end, int asaId, int amount, bool cancancel) async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    final List<RawTransaction> txns = [];

    final userAddr = session.accounts.first;

    // test that this works
    try {
      Address.fromAlgorandAddress(address: beneficiary);
    } catch (e) {
      return;
    }
    if (asaId <= 0) return;
    if (amount <= 0) return;
    final now = DateTime.now();
    if (end <= now.millisecondsSinceEpoch / 1000) return;

    final algoTxn = await (PaymentTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..receiver = Address.fromAlgorandAddress(address: CREATE_DAPP_ADDR[net]!)
          ..amount = 1000000
          ..suggestedParams = params)
        .build();
    txns.add(algoTxn);

    final argumentsOptIn = 'str:optin'.toApplicationArguments();
    final callOptInTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..arguments = argumentsOptIn
          ..foreignAssets = [asaId]
          ..applicationId = CREATE_DAPP_ID[net]!
          ..suggestedParams = params)
        .build();
    txns.add(callOptInTxn);

    final asaTxn = await (AssetTransferTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..receiver = Address.fromAlgorandAddress(address: CREATE_DAPP_ADDR[net]!)
          ..assetId = asaId
          ..amount = amount
          ..suggestedParams = params)
        .build();
    txns.add(asaTxn);

    final argumentsCreate =
        'str:create,int:${cancancel ? 1 : 0},int:$end,str:$NOTE_PREFIX_FOR$beneficiary by $userAddr,str:$NOTE_PREFIX_BY$userAddr 4 $beneficiary'
            .toApplicationArguments();
    final callCreateTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..arguments = argumentsCreate
          ..foreignAssets = [asaId]
          ..accounts = [Address.fromAlgorandAddress(address: beneficiary)]
          ..applicationId = CREATE_DAPP_ID[net]!
          ..suggestedParams = params)
        .build();
    txns.add(callCreateTxn);

    AtomicTransfer.group(txns);
    final txnsBytes = txns.map((txn) => Encoder.encodeMessagePack(txn.toMessagePack())).toList();
    final signedTxnsBytes = await provider.signTransactions(txnsBytes);

    return sendTxn(lib, signedTxnsBytes, () {});
  }

  int amount = 0;
  int end = 0;
  int? asaId;
  String beneficiary = '';
  bool cancancel = false;

  @override
  Widget build(BuildContext context) {
    return ItemCard(
      beneficiaryOnChanged: (String x) {
        beneficiary = x;
      },
      amountOnChanged: (String x) {
        amount = int.parse(x);
        setState(() {});
      },
      endOnChanged: (String x) {
        end = int.parse(x);
        setState(() {});
      },
      asas: assets,
      onASAChanged: (int? x) {
        asaId = x;
        setState(() {});
      },
      canCancelOnChanged: (x) {
        cancancel = x;
        setState(() {});
      },
      canCancel: cancancel,
      asaId: asaId, //asaId,
      amount: amount,
      end: end,
      onPressed: () => create(beneficiary, end, asaId!, amount, cancancel),
      action: 'create',
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

  // List<Transaction>? txns;
  List? txns;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    txns = await findTxns(net, '$NOTE_PREFIX_FOR${session.accounts.first}', CREATE_DAPP_ADDR[net]!); // [1, 2, 3, 4]; //
    setState(() {});
  }

  void withdraw(String dAppAddr, int dAppId, int asaId) async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    final List<RawTransaction> txns = [];

    final userAddr = session.accounts.first;

    final algoTxn = await (PaymentTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..receiver = Address.fromAlgorandAddress(address: dAppAddr)
          ..amount = 1000
          ..suggestedParams = params)
        .build();
    txns.add(algoTxn);

    final arguments = 'str:withdraw'.toApplicationArguments();
    final callTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..arguments = arguments
          ..applicationId = dAppId
          ..foreignAssets = [asaId]
          ..suggestedParams = params)
        .build();
    txns.add(callTxn);

    // if userAddr not opted-into asaId
    if (!await isOptedIs(userAddr, asaId)) {
      final asaTxn = await (AssetTransferTransactionBuilder()
            ..sender = Address.fromAlgorandAddress(address: userAddr)
            ..receiver = Address.fromAlgorandAddress(address: userAddr)
            ..assetId = asaId
            ..amount = 0
            ..suggestedParams = params)
          .build();
      txns.add(asaTxn);
    }

    AtomicTransfer.group(txns);
    final txnsBytes = txns.map((txn) => Encoder.encodeMessagePack(txn.toMessagePack())).toList();
    print('withdraw - signTransactions');
    final signedTxnsBytes = await provider.signTransactions(txnsBytes);

    print('withdraw - sendTxn');
    return sendTxn(lib, signedTxnsBytes, () {});
  }

  Future<bool> isOptedIs(String addr, int asaId) async {
    final lib = AlgorandLib.lib[net]!;
    final accInfo = await lib.getAccountByAddress(addr);
    return accInfo.assets.map((e) => e.assetId).contains(asaId);
  }

  Widget txnTile(t) {
    // Widget txnTile(Transaction t) {
    final dAppId = t.innerTxns[2].applicationTransaction!.applicationId; // 92125658; //
    final dAppAddr = Address.forApplication(dAppId).encodedAddress; // 'FLQLJZ5ZJVAY6VYO2AGSPVTFPCOUAASNMUBTR37RGSU7HVYDPC77LYYLKA'; //

    final creator = t.innerTxns[2].note!.split(' ').toList()[2]; // 'FLQLJZ5ZJVAY6VYO2AGSPVTFPCOUAASNMUBTR37RGSU7HVYDPC77LYYLKA';

    return FutureBuilder(
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(
            title: Text('loading...'),
          );
        }
        final data = snapshot.data as List;
        final amount = data[0]; // 7000; //
        final asaId = data[1]; // 92125658; //
        final start = data[2]; // 1657580600; //
        final end = data[3]; // 1657580600; //

        return ItemCard(
          topTitleKey: 'dApp',
          topTitleValue: dAppAddr,
          topSubTitleKey: 'creator',
          topSubTitleValue: creator,
          amountOnChanged: null,
          endOnChanged: null,
          asas: null,
          onASAChanged: null,
          asaId: asaId,
          amount: amount,
          start: start,
          end: end,
          onPressed: () {
            return withdraw(dAppAddr, dAppId, asaId);
          },
          action: 'withdraw',
        );
      },
      future: Future.value(0), //txnFutureInfo(net, dAppId, dAppAddr),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        child: txns == null
            ? const Text('searching')
            : txns!.isEmpty
                ? const Text('your account is not the beneficiary of any AlgoVesting dApps')
                : ListView.separated(
                    itemCount: txns!.length,
                    separatorBuilder: (_, __) => SizedBox(height: 25),
                    itemBuilder: (_, ix) => txnTile(txns![ix]),
                    // padding: EdgeInsets.only(bottom: 50, top: 50),
                    // children: txns!.map(txnTile).toList(),
                  ));
  }
}

class Update extends StatefulWidget {
  Update(this.provider, this.net, this.session, {Key? key}) : super(key: key);

  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;

  @override
  State<Update> createState() => _UpdateState(provider, net, session);
}

class _UpdateState extends State<Update> {
  _UpdateState(this.provider, this.net, this.session);
  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;

  List<Transaction>? txns;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    txns = await findTxns(net, '$NOTE_PREFIX_BY${session.accounts.first}', CREATE_DAPP_ADDR[net]!);
    setState(() {});
  }

  Future update(String dAppAddr, int dAppId, int asaId, int end, int amount) async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    final List<RawTransaction> txns = [];

    final userAddr = session.accounts.first;

    final arguments = 'str:update,int:$end'.toApplicationArguments();
    final callTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..arguments = arguments
          ..applicationId = dAppId
          ..foreignAssets = [asaId]
          ..suggestedParams = params)
        .build();
    txns.add(callTxn);

    final asaTxn = await (AssetTransferTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..receiver = Address.fromAlgorandAddress(address: dAppAddr)
          ..assetId = asaId
          ..amount = amount
          ..suggestedParams = params)
        .build();
    txns.add(asaTxn);

    AtomicTransfer.group(txns);
    final txnsBytes = txns.map((txn) => Encoder.encodeMessagePack(txn.toMessagePack())).toList();
    final signedTxnsBytes = await provider.signTransactions(txnsBytes);

    return sendTxn(lib, signedTxnsBytes, () {});
  }

  Widget txnTile(Transaction t) {
    final dAppId = t.innerTxns[2].applicationTransaction!.applicationId; // 92125658; //
    final dAppAddr = Address.forApplication(dAppId).encodedAddress; // 'FLQLJZ5ZJVAY6VYO2AGSPVTFPCOUAASNMUBTR37RGSU7HVYDPC77LYYLKA'; //

    final base64Note = t.innerTxns[2].note!;
    final clearTextNote = stringToBase64.decode(base64Note);
    final beneficiary = clearTextNote.split(' ').toList()[2]; // 'FLQLJZ5ZJVAY6VYO2AGSPVTFPCOUAASNMUBTR37RGSU7HVYDPC77LYYLKA'; //

    return FutureBuilder(
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(
            title: Text('loading...'),
          );
        }
        final data = snapshot.data as List;
        final amount = data[0]; // 7000; //
        final asaId = data[1]; // 92125658; //
        final start = data[2]; // 1657580600; //
        final end = data[3]; // 1657580600; //
        final canCancel = data[4] == 0 ? false : true; // 1; //

        final rate = calcRate(start, end, amount);

        int newAmount = 0;
        int newEnd = 0;

        return ItemCard(
          topTitleKey: 'dApp',
          topTitleValue: dAppAddr,
          topSubTitleKey: 'beneficiary',
          topSubTitleValue: beneficiary,
          amountOnChanged: (String x) {
            newAmount = int.parse(x);
          },
          endOnChanged: (String x) {
            newEnd = int.parse(x);
          },
          asas: null,
          onASAChanged: null,
          canCancel: canCancel,
          asaId: asaId,
          amount: amount,
          start: start,
          end: end,
          onPressed: () {
            final newRate = calcRate(start, newEnd, amount + newAmount);
            if (newRate < rate) return null;
            return update(dAppAddr, dAppId, asaId, newEnd, newAmount);
          },
          action: 'update',
        );
      },
      future: txnFutureInfo(net, dAppId, dAppAddr),
    );
  }

  @override
  Widget build(BuildContext context) {
    return txns == null
        ? const Text('searching')
        : txns!.isEmpty
            ? const Text('your account is not the creator of any AlgoVesting dApps')
            : ListView(
                children: txns!.map(txnTile).toList(),
              );
  }
}

class Cancel extends StatefulWidget {
  Cancel(this.provider, this.net, this.session, {Key? key}) : super(key: key);

  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;

  @override
  State<Cancel> createState() => _CancelState(provider, net, session);
}

class _CancelState extends State<Cancel> {
  _CancelState(this.provider, this.net, this.session);

  AlgorandWalletConnectProvider provider;
  AlgorandNet net;
  SessionStatus session;

  List<Transaction>? txns;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    txns = await findTxns(net, '$NOTE_PREFIX_BY${session.accounts.first}', CREATE_DAPP_ADDR[net]!);
    setState(() {});
  }

  Future cancel(int dAppId) async {
    final lib = AlgorandLib.lib[net]!;
    final params = await lib.getSuggestedTransactionParams();

    final List<RawTransaction> txns = [];

    final userAddr = session.accounts.first;

    final arguments = 'str:cancel'.toApplicationArguments();
    final callTxn = await (ApplicationCallTransactionBuilder()
          ..sender = Address.fromAlgorandAddress(address: userAddr)
          ..arguments = arguments
          ..applicationId = dAppId
          ..suggestedParams = params)
        .build();
    txns.add(callTxn);

    AtomicTransfer.group(txns);
    final txnsBytes = txns.map((txn) => Encoder.encodeMessagePack(txn.toMessagePack())).toList();
    final signedTxnsBytes = await provider.signTransactions(txnsBytes);

    sendTxn(lib, signedTxnsBytes, () {});
  }

  Widget txnTile(Transaction t) {
    final dAppId = t.innerTxns[2].applicationTransaction!.applicationId;
    final dAppAddr = Address.forApplication(dAppId).encodedAddress;

    final note = t.innerTxns[2].note ?? '';

    // final TextEditingController _amountController = TextEditingController();
    // final TextEditingController _endController = TextEditingController();

    return FutureBuilder(
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ListTile(
            title: Text('loading...'),
          );
        }
        final data = snapshot.data as List;
        final amount = data[0];
        final asaId = data[1];
        final start = data[2];
        final end = data[3];

        return ItemCard(
          topTitleKey: 'dApp',
          topTitleValue: dAppAddr,
          topSubTitleKey: 'beneficiary',
          topSubTitleValue: note,
          // amountController: _amountController,
          amountOnChanged: null,
          // endController: _endController,
          endOnChanged: null,
          asas: null,
          onASAChanged: null,
          asaId: asaId,
          amount: amount,
          start: start,
          end: end,
          onPressed: () {
            return cancel(dAppId);
          },
          action: 'cancel',
        );
      },
      future: txnFutureInfo(net, dAppId, dAppAddr),
    );
  }

  @override
  Widget build(BuildContext context) {
    return txns == null
        ? const Text('searching')
        : txns!.isEmpty
            ? const Text('your account is not the creator of any AlgoVesting dApps')
            : ListView(
                children: txns!.map(txnTile).toList(),
              );
  }
}

class ItemCard extends StatelessWidget {
  ItemCard({
    this.topTitleKey,
    this.topTitleValue,
    this.topSubTitleKey,
    this.topSubTitleValue,
    this.amountOnChanged,
    this.beneficiaryOnChanged,
    this.canCancelOnChanged,
    this.canCancel = false,
    this.endOnChanged,
    this.asas,
    this.onASAChanged,
    this.asaId = 0,
    this.amount = 0,
    this.start,
    this.end = 0,
    this.onPressed,
    this.action = 'action',
    Key? key,
  }) : super(key: key);

  final small = true; //false;

  final String? topTitleKey;
  final String? topTitleValue;
  final String? topSubTitleKey;
  final String? topSubTitleValue;

  final List<int>? asas;
  final Function(int?)? onASAChanged;

  final Function(String)? amountOnChanged;
  final Function(String)? endOnChanged;
  final Function(String)? beneficiaryOnChanged;

  final Function(bool)? canCancelOnChanged;
  final bool canCancel;

  final Function()? onPressed;

  final int? asaId;
  final int amount;
  final String action;
  final int? start;
  final int end;

  @override
  Widget build(BuildContext context) {
    print('asaId=$asaId');

    return Card(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Container(
              alignment: AlignmentDirectional.bottomEnd,
              height: 50,
              child: (ElevatedButton(
                onPressed: onPressed,
                child: Text(
                  action,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: small ? 15 : 30),
                ),
              ))),
          (topTitleKey != null || topTitleValue != null || topSubTitleKey != null || topSubTitleValue != null)
              ? ListTile(
                  title: RichText(
                      text: TextSpan(text: '$topTitleKey ', style: TextStyle(fontWeight: FontWeight.bold), children: [
                    TextSpan(
                        style: TextStyle(fontWeight: FontWeight.normal),
                        text: topTitleValue,
                        recognizer: TapGestureRecognizer()..onTap = () => copy(context, topTitleValue)),
                    TextSpan(text: ' (canCancel ${canCancel ? 'true' : 'false'})', style: TextStyle(fontWeight: FontWeight.normal)),
                  ])),
                  // subtitle: Text('$topSubTitleKey $topSubTitleValue'),
                  subtitle: RichText(
                      text: TextSpan(text: '$topSubTitleKey ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey), children: [
                    TextSpan(
                        style: TextStyle(fontWeight: FontWeight.normal),
                        text: topTitleValue,
                        recognizer: TapGestureRecognizer()..onTap = () => copy(context, topTitleValue))
                  ])),
                )
              : Container(),
          amountOnChanged != null
              ? TextField(
                  onChanged: amountOnChanged,
                  decoration: const InputDecoration(
                      label: Text('# coins'),
                      helperText: 'how many coins do you want to lock?',
                      icon: Icon(Icons.monetization_on),
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                )
              : Container(),
          endOnChanged != null
              ? TextField(
                  onChanged: endOnChanged,
                  decoration: const InputDecoration(
                      label: Text('END timestamp'),
                      helperText: 'when all unlocked? [epoch=secs since 1970]',
                      icon: Icon(Icons.schedule),
                      border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                )
              : Container(),
          beneficiaryOnChanged != null
              ? TextField(
                  onChanged: beneficiaryOnChanged,
                  decoration: const InputDecoration(
                      label: Text('beneficiary addr'), helperText: 'Algorand account of beneficiary', icon: Icon(Icons.person), border: OutlineInputBorder()),
                )
              : Container(),
          canCancelOnChanged != null
              ? CheckboxListTile(
                  subtitle: Text('can the creator ever remove the coins?'),
                  controlAffinity: ListTileControlAffinity.leading,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                    side: BorderSide(width: 1, color: Colors.grey),
                  ),
                  side: BorderSide(width: 1),
                  contentPadding: EdgeInsets.symmetric(horizontal: 0),
                  title: const Text('CanCancel'),
                  value: canCancel,
                  onChanged: (x) => canCancelOnChanged!(x!),
                )
              : Container(),
          asas != null
              ? Row(children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.grey, style: BorderStyle.solid, width: 0.80),
                    ),
                    child: DropdownButton<int>(
                      hint: Text('which coin to lock? [ASA id]'),
                      icon: Icon(Icons.keyboard_arrow_down),
                      alignment: AlignmentDirectional.center,
                      items: asas!
                          .map((int e) => DropdownMenuItem<int>(
                              alignment: AlignmentDirectional.center,
                              value: e,
                              child: Text(
                                e.toString(),
                                textAlign: TextAlign.center,
                              )))
                          .toList(),
                      onChanged: onASAChanged,
                      value: asaId,
                    ),
                  ),
                ])
              : Container(),
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: Colors.grey,
            ),
            child: RichText(
              text: TextSpan(style: TextStyle(fontSize: small ? 13 : 20), text: '$amount locked until ', children: [
                TextSpan(text: end.toString(), recognizer: TapGestureRecognizer()..onTap = () => copy(context, end)),
                TextSpan(text: '\nwithdrawal rate = ${calcRate(start, end, amount).toStringAsPrecision(2)} ['),
                TextSpan(text: asaId.toString(), recognizer: TapGestureRecognizer()..onTap = () => copy(context, asaId)),
                TextSpan(text: '/sec]'),
              ]),
              // textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

////////////
/// functions
///`

Future<List<Transaction>> findTxns(AlgorandNet net, String prefix, String addr) async {
  final lib = AlgorandLib.lib[net]!;
  final searchResponse = await lib
      .indexer()
      .transactions()
      .whereTransactionType(TransactionType.APPLICATION_CALL)
      .afterMinRound(MIN_ROUND)
      .whereNotePrefix(prefix)
      .whereAddress(Address.fromAlgorandAddress(address: addr))
      .search();
  return searchResponse.transactions;
}

num calcRate(int? _start, int? end, int? amount) {
  num? start = _start;
  if (start == null) {
    final now = DateTime.now();
    start = now.millisecondsSinceEpoch / 1000;
  }
  if (amount == 0) return 0;
  if (end == null || amount == null) return 0;
  if (start <= end) return amount;
  return amount / (end - start);
}

Future<List> txnFutureInfo(AlgorandNet net, int appId, String appAddr) async {
  final lib = AlgorandLib.lib[net]!;

  final accInfoFuture = lib.getAccountByAddress(appAddr);
  final applicationSearchResponseFuture = lib.indexer().applications().whereApplicationId(appId).search(limit: 1);
  final futures = await Future.wait([accInfoFuture, applicationSearchResponseFuture]);
  final accInfo = futures[0] as AccountInformation;
  final applicationSearchResponse = futures[1] as SearchApplicationsResponse;

  final amount = accInfo.assets.first.amount;
  final asaId = accInfo.assets.first.assetId;

  final application = applicationSearchResponse.applications.first;
  int? end;
  int? start;
  int? canCancel;
  for (TealKeyValue kv in application.params.globalState) {
    if (kv.key == END_KEY) end = kv.value.uint;
    if (kv.key == START_KEY) start = kv.value.uint;
    if (kv.key == CANCANCEL_KEY) canCancel = kv.value.uint;
  }

  return [amount, asaId, start, end, canCancel];
}

Future sendTxn(Algorand lib, List<Uint8List> signedTxnsBytes, Function doneF) async {
  print('sendTxn');
  try {
    final txId = await lib.sendRawTransactions(signedTxnsBytes);
    print('txId = $txId');

    final pendingTxn = await lib.waitForConfirmation(txId);

    print('pendingTxn=${pendingTxn}');

    return doneF();
  } on AlgorandException catch (ex) {
    final cause = ex.cause;
    if (cause is dio.DioError) {
      print('AlgorandException ' + cause.response?.data['message']);
    }
  }
}

void copy(context, x) {
  Clipboard.setData(ClipboardData(text: x.toString()));
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: const Text('copied'),
    duration: Duration(milliseconds: 500),
  ));
}

class UnderConstruction extends StatelessWidget {
  const UnderConstruction({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(child: Text('UnderConstruction', style: TextStyle(fontSize: 30)));
  }
}
