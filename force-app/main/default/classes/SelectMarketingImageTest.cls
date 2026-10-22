@IsTest
private class SelectMarketingImageTest {

    @IsTest
    static void blankKeyMessage_returnsEmpty() {
        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = '';
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        System.assertEquals(1, out.size());
        System.assertEquals('', out[0].assetUrl);
        System.assertEquals('', out[0].imageBlockJson);
    }

    @IsTest
    static void retrieverSuccess_returnsTopHit_andImageBlockJson() {
        Test.setMock(HttpCalloutMock.class, new RetrieverMock(200,
            '{"results":[{"assetId__c":"abc","url__c":"https://cdn/x.jpg","altText__c":"alt text",'
          + '"title__c":"Hero","description__c":"d","locale__c":"en_US",'
          + '"campaign__c":"summer_sale","visualStyle__c":"editorial"}]}'));

        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = 'Summer sale hero';
        r.locale = 'en_US';
        r.campaign = 'summer_sale';

        Test.startTest();
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        Test.stopTest();

        System.assertEquals('https://cdn/x.jpg', out[0].assetUrl);
        System.assertEquals('alt text', out[0].altText);
        System.assertEquals('abc', out[0].assetId);
        System.assertEquals('summer_sale', out[0].campaign);
        System.assertEquals('editorial', out[0].visualStyle);
        System.assert(out[0].imageBlockJson.contains('lightning/html'), 'Should include a lightning/html block');
        System.assert(out[0].imageBlockJson.contains('https://cdn/x.jpg'), 'Should include the asset URL');
        System.assert(out[0].imageBlockJson.contains('alt text'), 'Should include alt text');
    }

    @IsTest
    static void retrieverEmpty_returnsEmptyStrings() {
        Test.setMock(HttpCalloutMock.class, new RetrieverMock(200, '{"results":[]}'));
        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = 'no match';
        Test.startTest();
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        Test.stopTest();
        System.assertEquals('', out[0].assetUrl);
        System.assertEquals('', out[0].imageBlockJson);
    }

    @IsTest
    static void retrieverError_isSwallowed() {
        Test.setMock(HttpCalloutMock.class, new RetrieverMock(500, 'boom'));
        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = 'anything';
        Test.startTest();
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        Test.stopTest();
        System.assertEquals('', out[0].assetUrl);
    }

    @IsTest
    static void htmlEscaping_handlesDangerousChars() {
        Test.setMock(HttpCalloutMock.class, new RetrieverMock(200,
            '{"results":[{"assetId__c":"a","url__c":"https://cdn/x.jpg?a=1&b=2",'
          + '"altText__c":"Pete \\"The Great\\" <editor>","title__c":"T"}]}'));

        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = 'anything';

        Test.startTest();
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        Test.stopTest();

        System.assert(out[0].imageBlockJson.contains('&amp;'),  'Should escape &');
        System.assert(out[0].imageBlockJson.contains('&quot;'), 'Should escape "');
        System.assert(out[0].imageBlockJson.contains('&lt;'),   'Should escape <');
        System.assert(out[0].imageBlockJson.contains('&gt;'),   'Should escape >');
        System.assert(!out[0].imageBlockJson.contains('<editor>'), 'Raw < should not survive');
    }

    private class RetrieverMock implements HttpCalloutMock {
        private Integer code; private String body;
        RetrieverMock(Integer c, String b) { code = c; body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(code);
            r.setBody(body);
            return r;
        }
    }
}
