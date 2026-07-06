// Sends market state payloads to the Node.js Bridge via WebRequest.
// This is the ONLY module that makes HTTP calls from the EA.

// NOTE: For WebRequest to work, the operator must add
// http://localhost:3001 to Tools > Options > Expert Advisors >
// "Allow WebRequest for listed URL" in the MT5 terminal.
// This cannot be set programmatically — it is a one-time manual step.

#include "Defines.mqh"

// ------------------------------------------------------------
// CBridgeClient
// ------------------------------------------------------------
class CBridgeClient
{
private:
   int   m_timeout_ms;

   // ------------------------------------------------------------
   // CharArrayToStringSafe — safely convert char array to string
   // ------------------------------------------------------------
   string CharArrayToStringSafe(char &arr[])
   {
      int len = ArraySize(arr);
      if(len == 0)
         return "";
      // MQL5's CharArrayToString stops at the first null terminator,
      // but we can also explicitly trim trailing zeros.
      string result = CharArrayToString(arr, 0, len);
      // Remove any trailing null characters that might have been included
      int pos = StringFind(result, "\0");
      if(pos >= 0)
         result = StringSubstr(result, 0, pos);
      return result;
   }

public:
   // ------------------------------------------------------------
   // Constructor
   // ------------------------------------------------------------
   CBridgeClient(int timeoutMs = 8000)
   {
      m_timeout_ms = timeoutMs;
   }

   // ------------------------------------------------------------
   // SendHeartbeat — POST jsonPayload to LEINTUM_BRIDGE_URL
   // ------------------------------------------------------------
   bool SendHeartbeat(string jsonPayload, string &outResponse)
   {
      return SendToUrl(LEINTUM_BRIDGE_URL, jsonPayload, outResponse);
   }

   // ------------------------------------------------------------
   // SendAlert — POST jsonPayload to LEINTUM_ALERT_URL
   // ------------------------------------------------------------
   bool SendAlert(string jsonPayload, string &outResponse)
   {
      return SendToUrl(LEINTUM_ALERT_URL, jsonPayload, outResponse);
   }

private:
   // ------------------------------------------------------------
   // SendToUrl — common implementation for both endpoints
   // ------------------------------------------------------------
   bool SendToUrl(const string url, string jsonPayload, string &outResponse)
   {
      // 1. Convert jsonPayload to char array, trimming null terminator
      char data[];
      int len = StringToCharArray(jsonPayload, data);
      if(len > 0)
         ArrayResize(data, len - 1);   // remove trailing zero byte

      // 2. Prepare result buffers
      char result[];
      string resultHeaders;

      // 3. Call WebRequest
      int httpStatus = WebRequest(
         "POST",
         url,
         "Content-Type: application/json\r\n",
         m_timeout_ms,
         data,
         result,
         resultHeaders
      );

      // 4. Check return value
      if(httpStatus == -1)
      {
         int lastError = GetLastError();
         PrintFormat("[LEINTUM] BridgeClient: WebRequest failed, error %d. "
            "Check that the URL is in Tools > Options > Expert Advisors > "
            "Allow WebRequest for listed URL.", lastError);
         outResponse = "";
         return false;
      }

      if(httpStatus < 200 || httpStatus >= 300)
      {
         PrintFormat("[LEINTUM] BridgeClient: HTTP status %d", httpStatus);
         outResponse = "";
         return false;
      }

      // 5. Convert response char array to string
      outResponse = CharArrayToStringSafe(result);
      return true;
   }
};
