import 'dart:convert';
import 'dart:typed_data';

import 'package:cms/state/models.dart';
import 'package:http/http.dart' as http;

class Api {
  static const String baseUrl = 'https://christmas.onecode.uk/api';

  static Future<String?> saveDesign(CharacterDesign design, Uint8List bytes) async {
    //final response = await http.post(Uri.parse('$baseUrl/designs'), body: design.toJson());
  String id = '';
  if(design.characterId == 0){
    id = 'A';
  }else if(design.characterId == 1){
    id = 'B';
  }else if(design.characterId == 2){
    id = 'C';
  }else if(design.characterId == 3){
    id = 'D';
  }

   final base64Image = base64Encode(bytes);
   final dataUriImage = "data:image/png;base64,$base64Image";
    try{
      
            final response = await http.post(
        Uri.parse(baseUrl),
        body: {
          'act': 'part_1',
          'key' : 'msCh25_Ari',
          'fileimage': dataUriImage,
          'selected_method': id,
          'person_name': design.userName,
        },
      );

   
           if (response.statusCode == 200) {
        final body = response.body;
        return body;
      } else {
        throw Exception(
          "Upload failed with status ${response.statusCode}: ${response.body}",
        );
      }
    }catch (e){
      throw Exception('Error saving design: $e');
    }
  }
}