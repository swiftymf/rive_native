import 'package:flutter/services.dart';
import 'package:rive_native/rive_native.dart' as rive;

import '../app.dart';
import '../rive_player.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ExampleOutOfBandAssets extends StatefulWidget {
  const ExampleOutOfBandAssets({super.key});

  @override
  State<ExampleOutOfBandAssets> createState() => _ExampleOutOfBandAssetsState();
}

class _ExampleOutOfBandAssetsState extends State<ExampleOutOfBandAssets> {
  String assetUniqueName(rive.FileAsset asset) =>
      '${asset.name}-${asset.assetId}';

  Future<Uint8List> loadBundleAsset(rive.FileAsset asset) async {
    final data = await rootBundle.load("assets/${asset.uniqueFilename}");
    return Uint8List.sublistView(data);
  }

  Future<Uint8List?> loadCDNAsset(rive.FileAsset asset) async {
    final url = '${asset.cdnBaseUrl}/${asset.cdnUuid}';
    final res = await http.get(Uri.parse(url));

    if (res.statusCode != 200) {
      debugPrint('Failed to hosted asset');

      return null;
    }

    return res.bodyBytes;
  }

  Future<Uint8List?> loadAsset(rive.FileAsset asset) async {
    if (asset.cdnUuid.isNotEmpty) {
      return await loadCDNAsset(asset);
    } else {
      return await loadBundleAsset(asset);
    }
  }

  Future<void> loadImage(
      rive.ImageAsset imageAsset, rive.Factory riveFactory) async {
    final bytes = await loadAsset(imageAsset);
    if (bytes == null) {
      return;
    }
    final image = await riveFactory.decodeImage(bytes);

    if (image != null) {
      imageAsset.renderImage(image);
      // Dispose the image and the image asset immediately. Otherwise, wait for garbage collection.
      image.dispose();
      imageAsset.dispose();
    }
  }

  Future<void> loadFont(
      rive.FontAsset fontAsset, rive.Factory riveFactory) async {
    final bytes = await loadAsset(fontAsset);
    if (bytes == null) {
      return;
    }
    final font = await riveFactory.decodeFont(bytes);

    if (font != null) {
      fontAsset.font(font);
      // Dispose the font and the font asset immediately. Otherwise, wait for garbage collection.
      font.dispose();
      fontAsset.dispose();
    }
  }

  Future<void> loadAudio(
      rive.AudioAsset audioAsset, rive.Factory riveFactory) async {
    final bytes = await loadAsset(audioAsset);
    if (bytes == null) {
      return;
    }
    final audioSource = await riveFactory.decodeAudio(bytes);
    if (audioSource != null) {
      audioAsset.audio(audioSource);
      // Dispose the audio source and the audio asset immediately. Otherwise, wait for garbage collection.
      audioSource.dispose();
      audioAsset.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RivePlayer(
      asset: "assets/out_of_band.riv",
      artboardName: "Artboard",
      stateMachineName: "State Machine 1",
      assetLoader: (rive.FileAsset asset, Uint8List? bytes) {
        debugPrint("asset ID: ${asset.assetId}");
        debugPrint("asset Name: ${asset.name}");
        debugPrint("asset FileExtension: ${asset.fileExtension} ");
        debugPrint("asset cdnBaseUrl: ${asset.cdnBaseUrl}");
        debugPrint("asset cdnUuid: ${asset.cdnUuid}");
        debugPrint("asset runtime-type: ${asset.runtimeType}");

        if (bytes != null && bytes.isNotEmpty) {
          debugPrint("asset bytes length: ${bytes.length}");
          return false; // Asset is embedded in the .riv file, let Rive load it
        }

        switch (asset) {
          case rive.ImageAsset imageAsset:
            loadImage(imageAsset, RiveExampleApp.getCurrentFactory);
          case rive.FontAsset fontAsset:
            loadFont(fontAsset, RiveExampleApp.getCurrentFactory);
          case rive.AudioAsset audioAsset:
            loadAudio(audioAsset, RiveExampleApp.getCurrentFactory);
          case rive.UnknownAsset asset:
            debugPrint("Unknown asset, asset name: ${asset.name}");
        }

        return true; // Tell Rive not to load the asset, we will handle it.
      },
    );
  }
}
