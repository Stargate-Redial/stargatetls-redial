/*
 * LD_PRELOAD for the Linux Source 2007 srcds (SteamCMD app 310, depot 311, 2014: engine_i486.so md5 99d41901...).
 *
 * Ghost players. CSteam3::NotifyLocalClientConnect registers every fake client (bot) with Steam
 * (CreateUnauthenticatedUserConnection), but CSteam3::NotifyClientDisconnect returns at once for fake clients:
 *
 *     if ( client->IsFakeClient() ) return;                  <- every bot leaves here
 *     if ( client->IsFakeClient() ) SendUserDisconnect( *client->m_SteamID, userid );   <- dead code
 *     else ... (human players)
 *
 * Steam is never told that a bot left, and its player list (which answers the A2S queries of the server browser)
 * keeps them: +10 "players" at each map change with 10 bots (20/32, 30/32... while status says 10).
 * The fix removes the first "jne" (2 bytes -> nop), so bots take the branch written for them.
 *
 * The engine is dlopen'ed by dedicated_i486.so after this library's constructor ran: dlopen is wrapped, and the
 * engine is patched right after it loads. The 7 bytes around the jump are checked first; another engine build is
 * left alone (and said so on stderr).
 * Build: gcc -m32 -shared -fPIC -O2 -o srcds2007_fix_i486.so srcds2007_fix.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static void *( *s_pfnDlopen )( const char *, int ) = NULL;
static int s_bDone = 0;

static void PatchEngine( void *hEngine )
{
	unsigned char *pFunction = (unsigned char *)dlsym( hEngine, "_ZN7CSteam322NotifyClientDisconnectEP11CBaseClient" );
	/* call *0x70(%edi) (IsFakeClient); test %al,%al; jne <return> */
	static const unsigned char aExpected[7] = { 0xFF, 0x57, 0x70, 0x84, 0xC0, 0x75, 0xDD };
	unsigned char *p = pFunction ? pFunction + 0x76 : NULL;
	if ( !p || memcmp( p, aExpected, sizeof( aExpected ) ) != 0 )
	{
		fprintf( stderr, "srcds2007_fix: unknown engine build, bot disconnect fix NOT applied\n" );
		return;
	}
	long iPage = sysconf( _SC_PAGESIZE );
	unsigned char *pStart = (unsigned char *)( (unsigned long)( p + 5 ) & ~( (unsigned long)iPage - 1 ) );
	size_t iLength = ( p + 7 ) - pStart;
	if ( mprotect( pStart, iLength, PROT_READ | PROT_WRITE | PROT_EXEC ) != 0 )
	{
		fprintf( stderr, "srcds2007_fix: mprotect failed, bot disconnect fix NOT applied\n" );
		return;
	}
	p[5] = 0x90;
	p[6] = 0x90;
	mprotect( pStart, iLength, PROT_READ | PROT_EXEC );
	fprintf( stderr, "srcds2007_fix: Steam3 disconnect of bots restored (no ghost players)\n" );
}

void *dlopen( const char *szFile, int iMode )
{
	if ( !s_pfnDlopen )
		s_pfnDlopen = (void *( * )( const char *, int ))dlsym( RTLD_NEXT, "dlopen" );
	void *h = s_pfnDlopen( szFile, iMode );
	if ( h && szFile && !s_bDone )
	{
		size_t n = strlen( szFile );
		if ( n >= 14 && strcmp( szFile + n - 14, "engine_i486.so" ) == 0 )
		{
			s_bDone = 1;
			PatchEngine( h );
		}
	}
	return h;
}
