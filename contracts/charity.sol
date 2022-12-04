/**
 * @title Blockchain Charity
 * @author https://github.com/01Joseph-Hwang10
 * @dev 
 * IE421 팀플용 컨트랙트 implementation. 
 * 주로 [TheCrowdChain](https://github.com/syedMSohaib/thecrowdchain)을 참조했습니다.
 * 
 * `전체적 설명` 페이지 > 앱 작동 방식 섹션에 첨부한 다이어그램을 구현했습니다. 
 * 다이어그램과 다른 점은, Dapp admin account를 따로 두지 않고,
 * 대신 `Project` 컨트랙트의 `current` 변수에 기부자들의 모든 펀드를 모아둔 후,
 * `FundRequest` 컨트랙트를 통해 수혜자에게 펀드를 전송합니다.
 *
 * Note: 부족한 부분이 있다 싶으면 언제든지 수정해주세요.
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing OpenZeppelin's SafeMath Implementation
import '@openzeppelin/contracts/utils/math/SafeMath.sol';


// 아래는 저희 블록체인 기반 기부 플랫폼을 이루게 될 핵심 컨트랙트입니다.
// 이 컨트랙트는 기부자와 수혜자를 관리하고, 기부금을 관리하는 프로젝트를 관리합니다.
contract BlockchainCharity {
    using SafeMath for uint256;

    // 프로젝트 목록
    Project[] private projects;

    // 프로젝트 생성 이벤트
    // 프로젝트가 생성되면 이를 프론트엔드(UI)에 반영할 수 있습니다.
    event ProjectCreated(
        address causeAddress,
        address creator,
        string title,
        string projectType,
        string desciption
    );

    // 프로젝트를 새로 생성하는 함수입니다.
    // 외부에서 호출될 수 있는 external 함수입니다.   
    function startProject(
        string calldata title, 
        string calldata projectType, 
        string calldata description
    ) external {
        // Creating an object for project contract
        Project newProject = new Project(
            payable(msg.sender), 
            title, 
            projectType, 
            description
        );

        // Push in projects array created earlier
        projects.push(newProject);

        // Emit ProjectCreated event
        emit ProjectCreated(
            address(newProject),
            msg.sender,
            title,
            projectType,
            description
        );
    }

    // 모든 프로젝트 목록을 가져오는 함수입니다.
    // 프론트엔드(UI)에서 프로젝트 목록을 보여줄 때 사용됩니다.
    function getAllProjects() external view returns(Project[] memory ) {
        return projects;
    }
}

// 아래는 프로젝트를 관리하는 컨트랙트입니다.
// 
// `donate` 함수를 통해 기부자가 기부금을 기부할 수 있습니다.
contract Project {
    using SafeMath for uint256;

    // 프로젝트 상태를 정의하는 enum입니다.
    //
    // pending: 모금 중임을 의미합니다.
    // completed: 모금이 완료되었음을 의미합니다.
    enum State {
        pending,
        completed
    }

    // 프로젝트 생성자
    address payable public creator;
    // 현재 모금된 금액
    uint256 public current;
    // 프로젝트 제목
    string public title;
    // 프로젝트 유형
    string public projectType;
    // 프로젝트 설명
    string public description;

    // 프로젝트 상태
    State public state = State.pending;
    
    // 기부자 목록
    mapping(address => uint) public donors;
    uint256 public totalDonors;

    // 펀드 요청 목록
    FundRequest[] public fundRequests;

    // 컨트랙트가 기부금을 받았을 때 생성되는 이벤트입니다.
    event donationReceived(address donor, uint amount, uint current);

    // 기부금이 전부 모이고 이 기부금이 수혜자에게 전달되었을 때 생성되는 이벤트입니다.
    event donationSentToTarget(address recipient);

    // check the current state via modifier
    modifier checkState(State state_) {
        require(state == state_);
        _;
    }

    // check if caller is creator via modifier
    modifier isCreator() {
        require(msg.sender == creator);
        _;
    }

    // Check if caller is FundRequest via modifier
    modifier isFundRequest() {
        for (uint i = 0; i < fundRequests.length; i++) {
            require(msg.sender == address(fundRequests[i]));
            _;
        }
    }

    constructor(
        address payable _projectStarter,
        string memory _projectTitle,
        string memory _projectType,
        string memory _projectDescription
    ) {
        creator = _projectStarter;
        title = _projectTitle;
        projectType = _projectType;
        description = _projectDescription;
        current = 0;
    }

    // **프로젝트에 기부하는 함수입니다.**
    function donate() external checkState(State.pending) payable {
        require(msg.sender != creator);
        donors[msg.sender] = donors[msg.sender].add(msg.value);
        totalDonors++;
        current = current.add(msg.value);
        //emit donationReceived event
        emit donationReceived(msg.sender, msg.value, current);
    }

    // FundRequest에서 70% 이상의 donor의 투표를 받으면 호출되는 함수입니다.
    // FundRequest에서 정하는 value를 수혜자에게 전달합니다.
    function payToTarget(uint amount) public isFundRequest {
        require(current - amount >= 0);
        current -= amount;
        creator.transfer(amount);
        emit donationSentToTarget(creator);
    }

    // 펀드 요청을 생성합니다
    function createFundRequest(
        uint256 _value,
        string memory _description
    ) public isCreator {
        FundRequest newFundRequest = new FundRequest(
            address(this),
            _value,
            _description
        );
        fundRequests.push(newFundRequest);
    }

    // 모금을 완료합니다
    function finalizeProject() public isCreator {
        state = State.completed;
    }
}

// 프로젝트 생성자가 펀드 요청을 생성할 때 생성되는 컨트랙트입니다.
contract FundRequest {
    enum State {
        pending,
        resolved,
        rejected
    }
    
    // FundRequest 생성자. Project의 address여야합니다.
    address public recipient;
    // 요청하는 금액
    uint256 public value;
    // 요청한 사유
    string public description;
    State public state;
    uint256 public approvalCount;
    mapping(address => bool) public approvals;

    constructor(
        address _recipient, 
        uint256 _value, 
        string memory _description
    ) {
        recipient = _recipient;
        value = _value;
        description = _description;
        state = State.pending;
        approvalCount = 0;
    }

    // FundRequest를 생성한 프로젝트를 반환하는 함수입니다.
    function getProject() private view returns(Project) {
        return Project(recipient);
    }

    // Check if callar is donor from Project via modifier
    modifier isDonor {
        require(getProject().donors(msg.sender) > 0);
        _;
    }

    modifier isPending {
        require(state == State.pending);
        _;
    }

    // 기부자가 FundRequest승인에 투표하는 함수입니다.
    function approve() public isDonor isPending {
        approvals[msg.sender] = true;
        approvalCount++;

        Project project = getProject();
        // 70% 이상의 기부자가 펀드 요청을 승인하면 펀드 요청을 완료합니다.
        uint256 approvalThreshold = (project.totalDonors() * 70) / 100;
        if (approvalCount >= approvalThreshold) {
            project.payToTarget(value);
            state = State.resolved;
        }

        if (approvalCount == project.totalDonors()) {
            state = State.rejected;
        }
    }
}
