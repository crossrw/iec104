# IEC104

This is a simple implementation of an IEC 60870-5-104 data exchange server for Delphi & FPC.

I am not sure that all the requirements of the standard are fully met, but the test clients (QTester104 and Freyr SCADA client simulator), in my opinion, work correctly.

The server supports multiple simultaneous connections, the number is limited by the MAX_CLIENT_COUNT constant. The iec104_test.pas file contains a simple example of using the library.
