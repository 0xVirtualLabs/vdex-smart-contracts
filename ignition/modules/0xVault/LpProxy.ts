import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import VaultProxyModule from './VaultProxy';

/**
 * This is the first module that will be run. It deploys the proxy and the
 * proxy admin, and returns them so that they can be used by other modules.
 */
const lpProxyModule = buildModule('ProxyModule', (m) => {

    const proxyAdminOwner = m.getAccount(0);

    const { proxy: vaultProxy } = m.useModule(VaultProxyModule);

    const lpContract = m.contract('LpProvider', []);

    const proxy = m.contract('TransparentUpgradeableProxy', [
        lpContract, 
        proxyAdminOwner, 
        "0x"
      ]);
    
    const lpProxy = m.contractAt('LpProvider', proxy, {id: 'LpProxyInstance'});

    const proxyAdminAddress = m.readEventArgument(
    proxy,
    'AdminChanged',
    'newAdmin'
    );

    m.call(lpProxy, 'initialize', [proxyAdminOwner, vaultProxy], {
    from: proxyAdminOwner,
    });

    const proxyAdmin = m.contractAt('ProxyAdmin', proxyAdminAddress);

  // Return the proxy and proxy admin so that they can be used by other modules.
    return { proxyAdmin, lpProxy, proxy };
});

export default lpProxyModule;
