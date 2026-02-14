import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.Jenkins

def jenkins = Jenkins.getInstance()

if (jenkins.getSecurityRealm() instanceof HudsonPrivateSecurityRealm) {
  // Set password, let CasC handle the rest of the configuration
  def username = System.getProperty('user.name')
  def password = username
  jenkins.getSecurityRealm().createAccount(username, password)
}
