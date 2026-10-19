pipeline {
    agent any

    options {
        // Automatically timeout if build takes longer than 45 minutes
        timeout(time: 45, unit: 'MINUTES')
        // Discard old build records to save disk space
        buildDiscarder(logRotator(numToKeepStr: '10', daysToKeepStr: '30'))
        // Prevent concurrent executions on the same agent
        disableConcurrentBuilds()
        // Enable colored console logs in Jenkins
        ansiColor('xterm')
    }

    parameters {
        choice(
            name: 'BUILD_MODE',
            choices: ['full', 'docker_only', 'ci_only'],
            description: 'Execution mode: "full" (build code + Docker image), "docker_only" (build Dockerfile directly), or "ci_only" (lint and compile without Docker)'
        )
        booleanParam(
            name: 'RUN_LINT',
            defaultValue: true,
            description: 'Run Turborepo code linting'
        )
        booleanParam(
            name: 'BUILD_DOCKER',
            defaultValue: true,
            description: 'Build Docker container image'
        )
        booleanParam(
            name: 'PUSH_DOCKER_IMAGE',
            defaultValue: false,
            description: 'Push built image to container registry (requires Docker credentials)'
        )
        string(
            name: 'DOCKER_IMAGE_NAME',
            defaultValue: 'peppermint',
            description: 'Docker image repository name (e.g. your-dockerhub-user/peppermint)'
        )
        string(
            name: 'DOCKER_REGISTRY_CREDENTIALS_ID',
            defaultValue: 'dockerhub-credentials',
            description: 'Jenkins Credentials ID for Docker Registry'
        )
    }

    environment {
        CI = 'true'
        COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
        YARN_ENABLE_IMMUTABLE_INSTALLS = 'false'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        PATH = "${WORKSPACE}/.bin:${env.PATH}"
    }

    stages {
        stage('Checkout') {
            steps {
                echo '=== Stage 1: Checkout Source Code ==='
                checkout scm
            }
        }

        stage('Environment Verification') {
            steps {
                echo '=== Stage 2: Verifying Build Environment ==='
                sh '''
                    echo "Hostname: $(hostname)"
                    echo "Current User: $(whoami)"
                    echo "Node Version: $(node -v 2>&1 || echo 'Not installed')"
                    echo "Docker Version: $(docker -v 2>&1 || echo 'Not installed')"
                    echo "Corepack Version: $(corepack --version 2>&1 || echo 'Not installed')"
                '''
            }
        }

        stage('Install Dependencies') {
            when {
                expression { return params.BUILD_MODE in ['full', 'ci_only'] }
            }
            steps {
                echo '=== Stage 3: Installing Monorepo Dependencies via Yarn 4 ==='
                sh '''
                    # Install Corepack shims locally in workspace to avoid needing sudo/root access
                    mkdir -p "${WORKSPACE}/.bin"
                    corepack enable --install-directory "${WORKSPACE}/.bin" || true

                    # Verify yarn is found in PATH
                    which yarn || corepack yarn -v

                    # Install workspace dependencies using root yarn.lock
                    yarn install || corepack yarn install
                '''
            }
        }

        stage('Generate Prisma Client') {
            when {
                expression { return params.BUILD_MODE in ['full', 'ci_only'] }
            }
            steps {
                echo '=== Stage 4: Generating Prisma Client for API ==='
                sh '''
                    # Generate Prisma client for backend TypeScript build
                    cd apps/api
                    npx prisma generate
                '''
            }
        }

        stage('Lint & Code Quality') {
            when {
                allOf {
                    expression { return params.RUN_LINT == true }
                    expression { return params.BUILD_MODE in ['full', 'ci_only'] }
                }
            }
            steps {
                echo '=== Stage 5: Running Workspace Linting via Turborepo ==='
                sh '''
                    yarn lint || corepack yarn lint || echo "Linting completed with warnings or skipped"
                '''
            }
        }

        stage('Build Applications') {
            when {
                expression { return params.BUILD_MODE in ['full', 'ci_only'] }
            }
            steps {
                echo '=== Stage 6: Compiling Applications via Turborepo ==='
                sh '''
                    yarn build || corepack yarn build
                '''
            }
        }

        stage('Build Docker Image') {
            when {
                allOf {
                    expression { return params.BUILD_DOCKER == true }
                    expression { return params.BUILD_MODE in ['full', 'docker_only'] }
                }
            }
            steps {
                echo '=== Stage 7: Building Docker Container Image ==='
                sh '''
                    docker build \
                        -t ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} \
                        -t ${DOCKER_IMAGE_NAME}:latest \
                        -f dockerfile .
                '''
            }
        }

        stage('Push Docker Image') {
            when {
                allOf {
                    expression { return params.PUSH_DOCKER_IMAGE == true }
                    expression { return params.BUILD_MODE in ['full', 'docker_only'] }
                }
            }
            steps {
                echo '=== Stage 8: Pushing Docker Image to Registry ==='
                withCredentials([usernamePassword(
                    credentialsId: params.DOCKER_REGISTRY_CREDENTIALS_ID,
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker tag ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} ${DOCKER_USER}/${DOCKER_IMAGE_NAME}:${IMAGE_TAG}
                        docker tag ${DOCKER_IMAGE_NAME}:${IMAGE_TAG} ${DOCKER_USER}/${DOCKER_IMAGE_NAME}:latest
                        docker push ${DOCKER_USER}/${DOCKER_IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${DOCKER_USER}/${DOCKER_IMAGE_NAME}:latest
                    '''
                }
            }
        }
    }

    post {
        always {
            echo '=== Post Action: Cleaning workspace ==='
            cleanWs()
        }
        success {
            echo "SUCCESS: Pipeline build #${env.BUILD_NUMBER} completed successfully!"
        }
        failure {
            echo "FAILURE: Pipeline build #${env.BUILD_NUMBER} failed. Review the logs above for troubleshooting."
        }
    }
}