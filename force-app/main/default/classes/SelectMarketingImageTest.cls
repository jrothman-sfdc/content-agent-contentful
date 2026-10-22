@IsTest
private class SelectMarketingImageTest {

    @IsTest
    static void blankKeyMessage_returnsEmpty() {
        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = '';
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        System.assertEquals(1, out.size());
        System.assertEquals('', out[0].assetUrl);
        System.assertEquals('', out[0].assetId);
    }

    @IsTest
    static void retrieverSuccess_returnsTopHit() {
        Test.setMock(HttpCalloutMock.class, new RetrieverMock(200,
            '{"results":[{"assetId__c":"abc","url__c":"https://cdn/x.jpg","altText__c":"alt",'
          + '"campaign__c":"summer_sale","visualStyle__c":"editorial"}]}'));

        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = 'Summer sale hero';
        r.locale = 'en_US';
        r.campaign = 'summer_sale';

        Test.startTest();
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        Test.stopTest();

        System.assertEquals('https://cdn/x.jpg', out[0].assetUrl);
        System.assertEquals('abc', out[0].assetId);
        System.assertEquals('summer_sale', out[0].campaign);
        System.assertEquals('editorial', out[0].visualStyle);
    }

    @IsTest
    static void retrieverEmpty_returnsEmptyStrings() {
        Test.setMock(HttpCalloutMock.class, new RetrieverMock(200, '{"results":[]}'));

        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = 'no match for this one';

        Test.startTest();
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        Test.stopTest();

        System.assertEquals('', out[0].assetUrl);
    }

    @IsTest
    static void retrieverError_isSwallowed() {
        Test.setMock(HttpCalloutMock.class, new RetrieverMock(500, 'boom'));

        SelectMarketingImage.Request r = new SelectMarketingImage.Request();
        r.keyMessage = 'anything';

        Test.startTest();
        List<SelectMarketingImage.Response> out = SelectMarketingImage.run(new List<SelectMarketingImage.Request>{ r });
        Test.stopTest();

        System.assertEquals('', out[0].assetUrl, 'Errors should degrade gracefully to empty response for the POC');
    }

    private class RetrieverMock implements HttpCalloutMock {
        private Integer code;
        private String body;
        RetrieverMock(Integer c, String b) { code = c; body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse r = new HttpResponse();
            r.setStatusCode(code);
            r.setBody(body);
            return r;
        }
    }
}
