from git import Repo
from os import environ
import tempfile, boto3, docker, base64, logging

class FetchAndStoreFromECR:
    def __init__(self, regionName, profileName=""):
        self.logger = logging.getLogger(type(self).__name__)

        kwargs = {
            'region_name': regionName
        }
        if profileName:
            kwargs['profile_name'] = profileName

        session = boto3.Session(**kwargs)
        ecr = session.client('ecr')

        auth = ecr.get_authorization_token()['authorizationData'][0]

        username, token = base64.b64decode(auth['authorizationToken']).decode().split(":")
        self.auth = {
            'username': username,
            'password': token,
            'registry': auth['proxyEndpoint']
        }

        self.client = docker.from_env()
        self.client.login(**self.auth)
    
    def getLatestCommitSha(self, url, branch="main"):
        with tempfile.TemporaryDirectory() as tmpDir:
            self.logger.info(f"Temporary Dir: {tmpDir}")
            workingTree = Repo.clone_from(url, tmpDir)
            commitPrefix = workingTree.commit(branch).hexsha[:9]

        return commitPrefix

    def getDigest(self, image):
        tag = f"{image.attrs['Id'].replace(":", "-")}.att"
        self.logger.info(f"Image Digest: {tag}")
        return tag

    def fetch(self, repo, tag="latest", auth={}):
        res = self.client.images.pull(repo, tag=tag, auth_config=auth)
        self.logger.info(res)
        return res

    def tag(self, image, repo: str, tag: str):
        res = image.tag(repo, tag=tag)
        self.logger.info(res)
        return res

    def store(self, repo, tag="latest", auth={}):
        res = self.client.images.push(repo, tag=tag, auth_config=auth, stream=True, decode=True)
        for line in res:
            self.logger.info(line)
        return res
    
    def fetch_and_store(self, desired, desiredTag, target, targetTag=""):
        image = self.fetch(desired, desiredTag)
        if not targetTag:
            targetTag = self.getDigest(image)
        self.tag(image, target, targetTag)
        self.store(target, targetTag, self.auth)

profileName = environ.get("AWS_PROFILE_NAME", "")
accountId = environ.get("AWS_ACCOUNT_ID")
regionName = environ.get("AWS_REGION", "us-east-2")
desiredImg = environ.get("DESIRED_IMAGE", "ghcr.io/coder/coder-preview")
desiredTag = environ.get("DESIRED_TAG", "latest")
targetImg = environ.get("TARGET_IMAGE", f"{accountId}.dkr.ecr.{regionName}.amazonaws.com/coder-preview")
targetTag = environ.get("TARGET_TAG", "")
gitUrl = environ.get("GIT_URL", "https://github.com/coder/coder")

logging.basicConfig(level=logging.INFO)

client = FetchAndStoreFromECR(regionName, profileName)

client.fetch_and_store(
    desiredImg, desiredTag,
    targetImg, targetTag
)

client.fetch_and_store(
    desiredImg, desiredTag,
    targetImg, "latest"
)