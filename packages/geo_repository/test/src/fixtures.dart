// Real responses of the APIs (captured on 2026-10-01).

/// `GET data.geopf.fr/geocodage/search/?q=12 rue de la colombe chaponost`.
const searchResponse =
    '''{"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [4.739579, 45.707956]}, "properties": {"label": "12 rue de la Colombe 69630 Chaponost", "score": 0.9588118181818182, "housenumber": "12", "id": "69043_jj2dze_00012", "banId": "dd5698a6-31fa-4e8e-ab04-28ff4a1604fe", "name": "12 rue de la Colombe", "postcode": "69630", "citycode": "69043", "x": 835334.68, "y": 6513533.01, "city": "Chaponost", "context": "69, Rhône, Auvergne-Rhône-Alpes", "type": "housenumber", "importance": 0.54693, "depcode": "69", "street": "rue de la Colombe", "_type": "address"}}], "query": "12 rue de la colombe chaponost"}''';

/// `GET data.geopf.fr/geocodage/reverse/?lon=4.739579&lat=45.707956`.
const reverseResponse =
    '''{"type": "FeatureCollection", "features": [{"type": "Feature", "geometry": {"type": "Point", "coordinates": [4.739579, 45.707956]}, "properties": {"type": "housenumber", "name": "12 rue de la Colombe", "label": "12 rue de la Colombe 69630 Chaponost", "street": "rue de la Colombe", "postcode": "69630", "citycode": "69043", "city": "Chaponost", "oldcitycode": null, "oldcity": null, "context": "69, Rhône, Auvergne-Rhône-Alpes", "importance": 0.54693, "housenumber": "12", "id": "69043_jj2dze_00012", "banId": "dd5698a6-31fa-4e8e-ab04-28ff4a1604fe", "x": 835334.68, "y": 6513533.01, "distance": 0, "score": 1, "_type": "address"}}]}''';

/// `GET apicarto.ign.fr/api/cadastre/parcelle?geom=<point>`.
const parcelResponse =
    '''{"type": "FeatureCollection", "features": [{"type": "Feature", "id": "parcelle.83493213", "geometry": {"type": "MultiPolygon", "coordinates": [[[[4.73967502, 45.70803096], [4.7396389, 45.70799017], [4.73960607, 45.70795204], [4.73957742, 45.70791582], [4.73955891, 45.70789134], [4.73953632, 45.70785989], [4.7390696, 45.70799716], [4.73907934, 45.7080125], [4.7391325, 45.70809635], [4.73919945, 45.70820169], [4.73967502, 45.70803096]]]]}, "geometry_name": "geom", "properties": {"gid": 83355401, "numero": "0076", "feuille": 1, "section": "AM", "code_dep": "69", "nom_com": "Chaponost", "code_com": "043", "com_abs": "000", "code_arr": "000", "idu": "69043000AM0076", "contenance": 947, "code_insee": "69043"}}], "totalFeatures": 1, "numberMatched": 1, "numberReturned": 1, "timeStamp": "2026-09-30T22:11:49.177Z", "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:EPSG::4326"}}}''';
